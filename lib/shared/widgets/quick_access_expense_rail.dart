import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../modules/accounting/models/account.dart';
import '../../modules/accounting/models/expense.dart';
import '../../modules/accounting/models/expense_category.dart';
import '../../modules/accounting/models/expense_line.dart';
import '../../modules/accounting/services/accounting_service.dart';
import '../../modules/accounting/services/expense_service.dart';
import '../../modules/purchases/services/purchase_service.dart';
import '../models/payment_method.dart';
import '../models/supplier.dart' as shared_supplier;
import '../services/number_generation_service.dart';
import '../services/payment_method_service.dart';
import '../services/tenant_service.dart';
import '../utils/chilean_utils.dart';

enum _QuickExpenseTab {
  capture,
}

class QuickAccessExpenseRail extends StatefulWidget {
  const QuickAccessExpenseRail({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<QuickAccessExpenseRail> createState() => _QuickAccessExpenseRailState();
}

class _QuickAccessExpenseRailState extends State<QuickAccessExpenseRail> {
  final NumberFormat _numberFormat = NumberFormat('#,##0', 'es_CL');
  final NumberFormat _currencyFormat = ChileanUtils.currencyFormat;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _supplierController = TextEditingController();

  bool _isExpanded = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String? _bannerMessage;
  _QuickExpenseTab _activeTab = _QuickExpenseTab.capture;

  DateTime _expenseDate = DateTime.now();
  ExpenseDocumentType _documentType = ExpenseDocumentType.invoice;
  Account? _selectedAccount;
  ExpenseCategory? _selectedCategory;
  PaymentMethod? _selectedPaymentMethod;
  shared_supplier.Supplier? _selectedSupplier;

  List<Account> _accounts = const [];
  List<ExpenseCategory> _categories = const [];
  List<PaymentMethod> _paymentMethods = const [];
  List<shared_supplier.Supplier> _suppliers = const [];
  List<Expense> _recentExpenses = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _referenceController.dispose();
    _supplierController.dispose();
    super.dispose();
  }

  bool get _hasIva => _documentType == ExpenseDocumentType.invoice;

  double get _totalAmount => _parseAmount(_amountController.text);

  double get _netAmount {
    if (!_hasIva || _totalAmount <= 0) return _totalAmount;
    return _totalAmount / 1.19;
  }

  double get _ivaAmount {
    if (!_hasIva || _totalAmount <= 0) return 0;
    return _totalAmount - _netAmount;
  }

  Iterable<shared_supplier.Supplier> get _supplierSuggestions {
    final query = _supplierController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _suppliers.take(6);
    }

    return _suppliers.where((supplier) {
      return supplier.name.toLowerCase().contains(query) ||
          (supplier.rut?.toLowerCase().contains(query) ?? false) ||
          (supplier.phone?.toLowerCase().contains(query) ?? false);
    }).take(6);
  }

  double get _monthExpenseTotal {
    final now = DateTime.now();
    return _recentExpenses
        .where((expense) =>
            expense.issueDate.year == now.year &&
            expense.issueDate.month == now.month)
        .fold<double>(0, (sum, expense) => sum + expense.totalAmount);
  }

  double get _todayExpenseTotal {
    final now = DateTime.now();
    return _recentExpenses.where((expense) {
      final issueDate = expense.issueDate;
      return issueDate.year == now.year &&
          issueDate.month == now.month &&
          issueDate.day == now.day;
    }).fold<double>(0, (sum, expense) => sum + expense.totalAmount);
  }

  double get _pendingBalanceTotal {
    return _recentExpenses
        .where((expense) => expense.paymentStatus != ExpensePaymentStatus.paid)
        .fold<double>(0, (sum, expense) => sum + expense.balance);
  }

  int get _pendingExpenseCount {
    return _recentExpenses
        .where((expense) => expense.paymentStatus != ExpensePaymentStatus.paid)
        .length;
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final accountingService = context.read<AccountingService>();
      final expenseService = context.read<ExpenseService>();
      final purchaseService = context.read<PurchaseService>();
      final paymentMethodService = context.read<PaymentMethodService>();

      final results = await Future.wait([
        accountingService.getAccounts(),
        expenseService.fetchCategories(forceRefresh: refresh),
        expenseService.fetchExpenses(forceRefresh: refresh),
        purchaseService.getSuppliers(),
        paymentMethodService.loadPaymentMethods(forceRefresh: refresh),
        NumberGenerationService().previewExpenseNumber(),
      ]);

      final allAccounts = (results[0] as List<Account>)
          .where((account) =>
              account.type == AccountType.expense && account.isActive)
          .toList()
        ..sort((left, right) => left.code.compareTo(right.code));
      final categories = (results[1] as List<ExpenseCategory>)
        ..sort((left, right) => left.name.compareTo(right.name));
      final expenses = (results[2] as List<Expense>)
        ..sort((left, right) => right.issueDate.compareTo(left.issueDate));
      final suppliers = (results[3] as List<shared_supplier.Supplier>)
          .where((supplier) => supplier.isActive)
          .toList()
        ..sort((left, right) => left.name.compareTo(right.name));
      final methods =
          List<PaymentMethod>.from(paymentMethodService.paymentMethods)
            ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
      final nextNumber = results[5] as String;

      if (!mounted) return;

      setState(() {
        _accounts = allAccounts;
        _categories = categories;
        _recentExpenses = expenses.take(6).toList(growable: false);
        _suppliers = suppliers;
        _paymentMethods = methods;

        _selectedAccount ??= _resolveDefaultAccount(allAccounts);
        _selectedCategory ??=
            _resolveDefaultCategory(categories, _selectedAccount);
        _selectedPaymentMethod ??= _resolveDefaultPaymentMethod(methods);

        _bannerMessage = 'Próximo folio: $nextNumber';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Account? _resolveDefaultAccount(List<Account> accounts) {
    if (accounts.isEmpty) return null;
    for (final preferredCode in ['5200', '6100', '6101']) {
      final match = accounts.where((account) => account.code == preferredCode);
      if (match.isNotEmpty) return match.first;
    }
    return accounts.first;
  }

  ExpenseCategory? _resolveDefaultCategory(
    List<ExpenseCategory> categories,
    Account? selectedAccount,
  ) {
    if (categories.isEmpty) return null;
    if (selectedAccount != null) {
      final matchingCategories = categories.where(
        (category) => category.defaultAccountId == selectedAccount.id,
      );
      if (matchingCategories.isNotEmpty) {
        return matchingCategories.first;
      }
    }
    return null;
  }

  PaymentMethod? _resolveDefaultPaymentMethod(List<PaymentMethod> methods) {
    if (methods.isEmpty) return null;
    for (final preferredCode in ['cash', 'transfer', 'card']) {
      final match = methods.where((method) => method.code == preferredCode);
      if (match.isNotEmpty) return match.first;
    }
    return methods.first;
  }

  Future<void> _pickExpenseDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'CL'),
    );

    if (pickedDate == null || !mounted) return;
    setState(() => _expenseDate = pickedDate);
  }

  void _applyAmountPreset(int amount) {
    setState(() {
      _amountController.text = _numberFormat.format(amount);
    });
  }

  void _selectCategory(ExpenseCategory category) {
    setState(() {
      _selectedCategory = category;
      if (category.defaultAccountId != null) {
        for (final account in _accounts) {
          if (account.id == category.defaultAccountId) {
            _selectedAccount = account;
            break;
          }
        }
      }
    });
  }

  void _selectSupplier(shared_supplier.Supplier supplier) {
    setState(() {
      _selectedSupplier = supplier;
      _supplierController.text = supplier.name;
    });
  }

  void _clearSupplier() {
    setState(() {
      _selectedSupplier = null;
      _supplierController.clear();
    });
  }

  Future<void> _saveQuickExpense() async {
    FocusScope.of(context).unfocus();

    if (_selectedAccount?.id == null) {
      _showMessage('Selecciona una cuenta de gasto.', isError: true);
      return;
    }

    if (_selectedPaymentMethod == null) {
      _showMessage('Selecciona un método de pago.', isError: true);
      return;
    }

    if (_totalAmount <= 0) {
      _showMessage('Ingresa un monto válido.', isError: true);
      return;
    }

    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      _showMessage('Agrega una descripción corta para el gasto.',
          isError: true);
      return;
    }

    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) {
      _showMessage('No se pudo obtener el tenant actual.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final expenseNumber = await NumberGenerationService().nextExpenseNumber();
      final now = DateTime.now();
      final expense = Expense(
        tenantId: tenantId,
        expenseNumber: expenseNumber,
        categoryId: _selectedCategory?.id,
        supplierId: _selectedSupplier?.id,
        supplierName: _selectedSupplier?.name,
        supplierRut: _selectedSupplier?.rut,
        documentType: _documentType,
        documentNumber: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        issueDate: _expenseDate,
        currency: 'CLP',
        exchangeRate: 1,
        postingStatus: ExpensePostingStatus.posted,
        paymentStatus: ExpensePaymentStatus.paid,
        subtotal: _netAmount,
        taxAmount: _ivaAmount,
        totalAmount: _totalAmount,
        amountPaid: _totalAmount,
        balance: 0,
        notes: description,
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        approvalStatus: ExpenseApprovalStatus.approved,
        postedAt: now,
        paidAt: now,
        paymentAccountId: _selectedPaymentMethod!.accountId,
        paymentMethodId: _selectedPaymentMethod!.id,
        updatedAt: now,
        lines: [
          ExpenseLine(
            tenantId: tenantId,
            lineIndex: 0,
            accountId: _selectedAccount!.id!,
            accountCode: _selectedAccount!.code,
            accountName: _selectedAccount!.name,
            description: description,
            quantity: 1,
            unitPrice: _netAmount,
            subtotal: _netAmount,
            taxRate: _hasIva ? 19.0 : 0.0,
            taxAmount: _ivaAmount,
            total: _totalAmount,
          ),
        ],
      );

      await context.read<ExpenseService>().saveExpense(expense);
      if (!mounted) return;

      setState(() {
        _amountController.clear();
        _descriptionController.clear();
        _referenceController.clear();
        _expenseDate = DateTime.now();
        _documentType = ExpenseDocumentType.invoice;
      });
      _clearSupplier();
      await _loadData(refresh: true);
      _showMessage('Gasto $expenseNumber registrado.', isError: false);
    } catch (error) {
      _showMessage('No se pudo registrar el gasto: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message, {required bool isError}) {
    setState(() {
      _bannerMessage = message;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      ),
    );
  }

  double _parseAmount(String text) {
    if (text.trim().isEmpty) return 0;
    final normalized = text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM', 'es_CL').format(date);
  }

  String _documentTypeLabel(ExpenseDocumentType type) {
    switch (type) {
      case ExpenseDocumentType.invoice:
        return 'Factura';
      case ExpenseDocumentType.receipt:
        return 'Boleta';
      case ExpenseDocumentType.ticket:
        return 'Ticket';
      case ExpenseDocumentType.reimbursement:
        return 'Reembolso';
      case ExpenseDocumentType.other:
        return 'Otro';
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

  @override
  Widget build(BuildContext context) {
    if (!widget.embedded && MediaQuery.of(context).size.width < 1180) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    if (widget.embedded) {
      return Container(
        color: theme.colorScheme.surface,
        child: _buildPanel(theme),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 16, right: 16, bottom: 24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: _isExpanded ? 472 : 64,
          constraints: const BoxConstraints(maxHeight: 760),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.98),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Row(
            children: [
              if (_isExpanded) Expanded(child: _buildPanel(theme)),
              _buildRail(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRail(ThemeData theme) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.08),
            theme.colorScheme.surfaceContainerHigh,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(_isExpanded ? 0 : 28),
          bottomLeft: Radius.circular(_isExpanded ? 0 : 28),
          topRight: const Radius.circular(28),
          bottomRight: const Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          _RailButton(
            icon: Icons.receipt_long_rounded,
            tooltip: 'Caja de gastos',
            selected: _isExpanded && _activeTab == _QuickExpenseTab.capture,
            accentColor: const Color(0xFF0F9D58),
            onTap: () {
              setState(() {
                if (_isExpanded && _activeTab == _QuickExpenseTab.capture) {
                  _isExpanded = false;
                } else {
                  _isExpanded = true;
                  _activeTab = _QuickExpenseTab.capture;
                }
              });
            },
          ),
          const SizedBox(height: 10),
          _RailButton(
            icon: Icons.list_alt_rounded,
            tooltip: 'Abrir lista de gastos',
            accentColor: theme.colorScheme.primary,
            onTap: () => context.push('/accounting/expenses'),
          ),
          const SizedBox(height: 10),
          _RailButton(
            icon: Icons.sell_outlined,
            tooltip: 'Categorías de gastos',
            accentColor: const Color(0xFFFF8F00),
            onTap: () => context.push('/accounting/expense-categories'),
          ),
          const Spacer(),
          _RailButton(
            icon: _isExpanded
                ? Icons.chevron_right_rounded
                : Icons.chevron_left_rounded,
            tooltip: _isExpanded ? 'Contraer' : 'Expandir',
            accentColor: theme.colorScheme.secondary,
            onTap: () => setState(() => _isExpanded = !_isExpanded),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Expenses',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _loadError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _loadData(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme),
          const SizedBox(height: 18),
          _buildStats(theme),
          const SizedBox(height: 18),
          _buildFormCard(theme),
          const SizedBox(height: 18),
          _buildRecentExpenses(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withOpacity(0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.flash_on_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Expenses',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Registra un gasto pagado sin salir del módulo actual.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.84),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_bannerMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _bannerMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStats(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Hoy',
            value: _currencyFormat.format(_todayExpenseTotal),
            icon: Icons.today_rounded,
            accentColor: const Color(0xFF0F9D58),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Mes',
            value: _currencyFormat.format(_monthExpenseTotal),
            icon: Icons.insights_rounded,
            accentColor: const Color(0xFF1A73E8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Pendientes',
            value: _pendingExpenseCount == 0
                ? '0'
                : '${_pendingExpenseCount} · ${_currencyFormat.format(_pendingBalanceTotal)}',
            icon: Icons.schedule_rounded,
            accentColor: const Color(0xFFFF8F00),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Captura rápida',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => context.push('/accounting/expenses/new'),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: const Text('Módulo completo'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedButton<ExpenseDocumentType>(
            segments: const [
              ButtonSegment<ExpenseDocumentType>(
                value: ExpenseDocumentType.invoice,
                icon: Icon(Icons.receipt_long_outlined, size: 16),
                label: Text('Factura'),
              ),
              ButtonSegment<ExpenseDocumentType>(
                value: ExpenseDocumentType.receipt,
                icon: Icon(Icons.point_of_sale_outlined, size: 16),
                label: Text('Boleta'),
              ),
              ButtonSegment<ExpenseDocumentType>(
                value: ExpenseDocumentType.reimbursement,
                icon: Icon(Icons.replay_circle_filled_outlined, size: 16),
                label: Text('Reembolso'),
              ),
            ],
            selected: {_documentType},
            onSelectionChanged: _isSaving
                ? null
                : (selection) {
                    setState(() {
                      _documentType = selection.first;
                    });
                  },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            decoration: InputDecoration(
              labelText: 'Monto total',
              hintText: '45.000',
              prefixIcon: const Icon(Icons.payments_outlined),
              suffixText: 'CLP',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [10000, 25000, 50000, 100000]
                .map(
                  (amount) => ActionChip(
                    label: Text(_currencyFormat.format(amount)),
                    onPressed:
                        _isSaving ? null : () => _applyAmountPreset(amount),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Descripción',
              hintText: 'Ej: compra de insumos, combustible, mensajería...',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 28),
                child: Icon(Icons.notes_rounded),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Account>(
                  value: _selectedAccount,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Cuenta',
                    prefixIcon:
                        const Icon(Icons.account_balance_wallet_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: _accounts
                      .map(
                        (account) => DropdownMenuItem<Account>(
                          value: account,
                          child: Text('${account.code} · ${account.name}'),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (account) => setState(() => _selectedAccount = account),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<PaymentMethod>(
                  value: _selectedPaymentMethod,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Pago',
                    prefixIcon: const Icon(Icons.account_balance_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: _paymentMethods
                      .map(
                        (method) => DropdownMenuItem<PaymentMethod>(
                          value: method,
                          child: Text(method.name),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (method) =>
                          setState(() => _selectedPaymentMethod = method),
                ),
              ),
            ],
          ),
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Categoría sugerida',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories
                  .take(6)
                  .map(
                    (category) => ChoiceChip(
                      label: Text(category.name),
                      selected: _selectedCategory == category,
                      onSelected: _isSaving
                          ? null
                          : (selected) {
                              if (!selected) {
                                setState(() => _selectedCategory = null);
                                return;
                              }
                              _selectCategory(category);
                            },
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _supplierController,
            decoration: InputDecoration(
              labelText: 'Proveedor opcional',
              hintText: 'Buscar por nombre, RUT o teléfono',
              prefixIcon: const Icon(Icons.storefront_outlined),
              suffixIcon: _selectedSupplier != null
                  ? IconButton(
                      onPressed: _isSaving ? null : _clearSupplier,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Quitar proveedor',
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_supplierSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: _supplierSuggestions
                    .map(
                      (supplier) => ListTile(
                        dense: true,
                        minLeadingWidth: 0,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              theme.colorScheme.primary.withOpacity(0.12),
                          child: Icon(
                            Icons.person_2_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          supplier.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          supplier.rut ?? supplier.phone ?? 'Sin RUT',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _selectedSupplier?.id == supplier.id
                            ? Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                                size: 18,
                              )
                            : null,
                        onTap:
                            _isSaving ? null : () => _selectSupplier(supplier),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickExpenseDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text('Fecha ${_formatDate(_expenseDate)}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _referenceController,
                  decoration: InputDecoration(
                    labelText: 'Referencia',
                    hintText: 'N° doc / folio',
                    prefixIcon: const Icon(Icons.tag_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.35),
              ),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  label: 'Neto',
                  value: _currencyFormat.format(_netAmount),
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: _hasIva ? 'IVA 19%' : 'IVA',
                  value: _currencyFormat.format(_ivaAmount),
                  highlight: _hasIva,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Total a contabilizar',
                  value: _currencyFormat.format(_totalAmount),
                  emphasize: true,
                ),
                const SizedBox(height: 8),
                Text(
                  _hasIva
                      ? 'El monto ingresado incluye IVA y se desglosa automáticamente.'
                      : 'El monto se registrará sin impuestos en esta captura rápida.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveQuickExpense,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label:
                  Text(_isSaving ? 'Registrando...' : 'Registrar gasto ahora'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentExpenses(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recientes',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/accounting/expenses'),
                child: const Text('Ver todos'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_recentExpenses.isEmpty)
            Text(
              'Todavía no hay gastos recientes para mostrar.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Column(
              children: _recentExpenses
                  .map(
                    (expense) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: expense.id == null
                            ? null
                            : () => context
                                .push('/accounting/expenses/${expense.id}'),
                        child: Ink(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withOpacity(0.28),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.receipt_outlined,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      expense.notes ??
                                          expense.reference ??
                                          expense.expenseNumber,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        expense.expenseNumber,
                                        expense.supplierName,
                                        _paymentStatusLabel(
                                            expense.paymentStatus),
                                      ]
                                          .whereType<String>()
                                          .where((value) => value.isNotEmpty)
                                          .join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _currencyFormat.format(expense.totalAmount),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(expense.issueDate),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.accentColor,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final Color accentColor;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? accentColor.withOpacity(0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              color: selected ? accentColor : Theme.of(context).iconTheme.color,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlight = false,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool highlight;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = emphasize
        ? theme.colorScheme.primary
        : highlight
            ? const Color(0xFFFF8F00)
            : theme.colorScheme.onSurface;

    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: emphasize ? color : theme.colorScheme.onSurfaceVariant,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
