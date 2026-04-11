import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/models/payment_method.dart';
import '../../../shared/models/supplier.dart' as shared_supplier;
import '../../../shared/services/number_generation_service.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../accounting/models/account.dart';
import '../../accounting/services/accounting_service.dart';
import '../../purchases/services/purchase_service.dart';
import '../models/expense.dart';
import '../models/expense_line.dart';
import '../services/expense_service.dart';

/// Expense Form - Invoice-style two-column layout
class ExpenseFormPage extends StatefulWidget {
  const ExpenseFormPage({super.key, this.expenseId});

  final String? expenseId;

  @override
  State<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends State<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();

  late ExpenseService _expenseService;
  late AccountingService _accountingService;
  late PaymentMethodService _paymentMethodService;
  late PurchaseService _purchaseService;

  Expense? _existingExpense;
  List<Account> _expenseAccounts = const [];
  List<PaymentMethod> _paymentMethods = const [];
  List<shared_supplier.Supplier> _suppliers = const [];

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  // Form fields
  final TextEditingController _expenseNumberController =
      TextEditingController();
  final TextEditingController _totalController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  DateTime _date = DateTime.now();
  ExpenseDocumentType _documentType = ExpenseDocumentType.receipt;
  Account? _selectedAccount;
  PaymentMethod? _selectedPaymentMethod;
  shared_supplier.Supplier? _selectedSupplier;

  final NumberFormat _currencyFormat = ChileanUtils.currencyFormat;

  // Calculated values
  double get _totalPaid => _parseAmount(_totalController.text);
  bool get _hasIva => _documentType == ExpenseDocumentType.invoice;
  double get _netAmount =>
      (!_hasIva || _totalPaid <= 0) ? _totalPaid : _totalPaid / 1.19;
  double get _ivaAmount =>
      (!_hasIva || _totalPaid <= 0) ? 0 : _totalPaid - _netAmount;

  @override
  void initState() {
    super.initState();
    _expenseService = context.read<ExpenseService>();
    _accountingService = context.read<AccountingService>();
    _paymentMethodService = context.read<PaymentMethodService>();
    _purchaseService = context.read<PurchaseService>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _accountingService.getAccounts(),
        _paymentMethodService.loadPaymentMethods(forceRefresh: true),
        _purchaseService.getSuppliers(),
        if (widget.expenseId != null)
          _expenseService.getExpense(widget.expenseId!, forceRefresh: true)
        else
          Future<Expense?>.value(null),
      ]);

      final allAccounts = results[0] as List<Account>;
      _suppliers = results[2] as List<shared_supplier.Supplier>;
      final expense = results.length > 3 ? results[3] as Expense? : null;

      _expenseAccounts = allAccounts
          .where((a) => a.type == AccountType.expense && a.isActive)
          .toList()
        ..sort((a, b) => a.code.compareTo(b.code));

      _paymentMethods = _paymentMethodService.paymentMethods;

      if (expense != null) {
        _existingExpense = expense;
        _expenseNumberController.text = expense.expenseNumber;
        _totalController.text = _formatNumber(expense.totalAmount);
        _notesController.text = expense.notes ?? '';
        _referenceController.text = expense.reference ?? '';
        _date = expense.issueDate;
        _documentType = expense.documentType;

        if (expense.supplierId != null) {
          _selectedSupplier = _suppliers.firstWhere(
            (s) => s.id == expense.supplierId,
            orElse: () => _suppliers.first,
          );
        }

        if (expense.lines.isNotEmpty) {
          final firstLine = expense.lines.first;
          _descriptionController.text = firstLine.description ?? '';
          _selectedAccount = _expenseAccounts.firstWhere(
            (a) => a.id == firstLine.accountId,
            orElse: () => _expenseAccounts.firstWhere(
              (a) => a.code == firstLine.accountCode,
              orElse: () => _expenseAccounts.isNotEmpty
                  ? _expenseAccounts.first
                  : _fallbackAccount(firstLine),
            ),
          );
        }

        if (expense.paymentMethodId != null) {
          _selectedPaymentMethod = _paymentMethods.firstWhere(
            (m) => m.id == expense.paymentMethodId,
            orElse: () => _paymentMethods.first,
          );
        }
      } else {
        // Preview expense number (doesn't increment until save)
        _expenseNumberController.text = await _previewExpenseNumber();

        if (_expenseAccounts.isNotEmpty) {
          _selectedAccount = _expenseAccounts.firstWhere(
            (a) => a.code == '6801' || a.code == '680100',
            orElse: () => _expenseAccounts.first,
          );
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Account _fallbackAccount(ExpenseLine line) {
    return Account(
      id: line.accountId,
      tenantId: '',
      code: line.accountCode,
      name: line.accountName,
      type: AccountType.expense,
      category: AccountCategory.operatingExpense,
    );
  }

  /// Preview what the next expense number will be (doesn't increment counter)
  /// Used when entering form - actual number assigned only on save
  Future<String> _previewExpenseNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.previewExpenseNumber();
    } catch (e) {
      if (kDebugMode) print('Error previewing expense number: $e');
      return 'GTO-0001'; // Fallback
    }
  }

  /// Generate the actual expense number (increments counter)
  /// Used only when actually SAVING a new expense
  Future<String> _generateExpenseNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.nextExpenseNumber();
    } catch (e) {
      if (kDebugMode) print('Error generating expense number: $e');
      return 'GTO-0001'; // Fallback
    }
  }

  @override
  void dispose() {
    _expenseNumberController.dispose();
    _totalController.dispose();
    _notesController.dispose();
    _referenceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: widget.expenseId != null ? 'Editar gasto' : 'Nuevo gasto',
      body: _isLoading
          ? const Center(child: BrandedLoading())
          : _error != null
              ? _buildErrorState(context)
              : _buildForm(context),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error, size: 48),
          const SizedBox(height: 12),
          const Text('No se pudo cargar el formulario'),
          const SizedBox(height: 8),
          Text(_error ?? 'Error desconocido'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Top bar with title and save button
          _buildTopBar(context),

          // Main content - two columns
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Standard breakpoint for this 2-column layout
                  if (constraints.maxWidth < 900) {
                    return Column(
                      children: [
                        // Main form (full width)
                        Column(
                          children: [
                            _buildCard(
                              context,
                              icon: Icons.receipt_long_outlined,
                              title: 'Detalle del gasto',
                              child: _buildExpenseDetailsSection(context),
                            ),
                            const SizedBox(height: 16),
                            _buildCard(
                              context,
                              icon: Icons.notes_outlined,
                              title: 'Referencia',
                              child: _buildReferenceSection(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Summary sidebar (full width on mobile)
                        SizedBox(
                          width: double.infinity,
                          child: _buildSidebar(context),
                        ),
                      ],
                    );
                  }

                  // Desktop: 2 columns
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left column - Main form
                      Expanded(
                        flex: 7,
                        child: Column(
                          children: [
                            _buildCard(
                              context,
                              icon: Icons.receipt_long_outlined,
                              title: 'Detalle del gasto',
                              child: _buildExpenseDetailsSection(context),
                            ),
                            const SizedBox(height: 16),

                            // Reference section
                            _buildCard(
                              context,
                              icon: Icons.notes_outlined,
                              title: 'Referencia',
                              child: _buildReferenceSection(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),

                      // Right column - Summary sidebar
                      SizedBox(
                        width: 320,
                        child: _buildSidebar(context),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;

          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        onPressed: _isSaving ? null : () => context.pop(false),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Volver',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.expenseId == null
                            ? 'Nuevo gasto'
                            : 'Editar gasto',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _handleSave,
                  icon: _isSaving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              // Back button
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: _isSaving ? null : () => context.pop(false),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Volver',
                ),
              ),
              const SizedBox(width: 16),

              // Title only - expense number shown only when editing
              Expanded(
                child: Text(
                  widget.expenseId == null ? 'Nuevo gasto' : 'Editar gasto',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Save button
              FilledButton.icon(
                onPressed: _isSaving ? null : _handleSave,
                icon: _isSaving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseDetailsSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Expense number row (first)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Número'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _expenseNumberController,
                    readOnly: true,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Account and Amount row
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              return Column(
                children: [
                  _buildAccountField(context),
                  const SizedBox(height: 16),
                  _buildAmountField(context),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Account
                Expanded(
                  flex: 3,
                  child: _buildAccountField(context),
                ),
                const SizedBox(width: 16),
                // Amount
                SizedBox(
                  width: 180,
                  child: _buildAmountField(context),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // Supplier row (compact)
        _buildFieldLabel('Proveedor (opcional)'),
        const SizedBox(height: 8),
        InkWell(
          onTap: _openSupplierPicker,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.store_outlined,
                    size: 18, color: Colors.grey.shade500),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedSupplier?.name ?? 'Seleccionar proveedor...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _selectedSupplier != null
                          ? null
                          : Colors.grey.shade500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_selectedSupplier != null)
                  GestureDetector(
                    onTap: () => setState(() => _selectedSupplier = null),
                    child: Icon(Icons.close,
                        size: 18, color: Colors.grey.shade500),
                  )
                else
                  Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Description
        _buildFieldLabel('Descripción (opcional)'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Describe el gasto...',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountField(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('Cuenta de gastos'),
        const SizedBox(height: 8),
        InkWell(
          onTap: _expenseAccounts.isEmpty ? null : _openAccountPicker,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: _selectedAccount == null
                    ? theme.colorScheme.error
                    : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedAccount != null
                        ? '${_selectedAccount!.code} - ${_selectedAccount!.name}'
                        : 'Seleccione una cuenta',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _selectedAccount != null
                          ? null
                          : Colors.grey.shade500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountField(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('Monto'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _totalController,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          validator: (value) {
            if (_parseAmount(value) <= 0) return 'Requerido';
            return null;
          },
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildReferenceSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _referenceController,
          decoration: InputDecoration(
            labelText: 'Referencia (opcional)',
            hintText: 'N° factura, boleta, etc.',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notesController,
          maxLines: 2,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: 'Notas internas (opcional)',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Dates and Status card
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Fechas y estado',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),

              // Date row
              _buildSidebarRow(
                context,
                icon: Icons.event,
                label: 'Fecha del gasto',
                value: ChileanUtils.formatDate(_date),
                action: 'Cambiar',
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),

              // Document type
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined,
                        size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tipo de documento',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<ExpenseDocumentType>(
                            initialValue: _documentType,
                            isExpanded: true,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            items: ExpenseDocumentType.values.map((type) {
                              return DropdownMenuItem(
                                value: type,
                                child: Text(_documentTypeLabel(type)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _documentType = value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // IVA treatment
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.receipt_outlined,
                        size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tratamiento de IVA',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _hasIva
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _hasIva
                                    ? Colors.green.shade200
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              _hasIva ? 'Con IVA (19%)' : 'Sin IVA (exento)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _hasIva
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Payment method
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pagado con',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<PaymentMethod>(
                            initialValue: _selectedPaymentMethod,
                            isExpanded: true,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            items: _paymentMethods.map((method) {
                              return DropdownMenuItem(
                                value: method,
                                child: Text(method.name,
                                    overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (value) =>
                                setState(() => _selectedPaymentMethod = value),
                            validator: (value) =>
                                value == null ? 'Requerido' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Summary card
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.summarize_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Resumen',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),

              // Amounts
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildSummaryRow('Subtotal (Neto)', _netAmount),
                    if (_hasIva) ...[
                      const SizedBox(height: 8),
                      _buildSummaryRow('IVA Crédito (19%)', _ivaAmount,
                          isHighlight: true),
                    ],
                    const SizedBox(height: 12),
                    Divider(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300),
                    const SizedBox(height: 12),
                    _buildSummaryRow('Total', _totalPaid, isTotal: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    String? action,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (action != null && onTap != null)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    double amount, {
    bool isTotal = false,
    bool isHighlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 15 : 13,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
            color: isHighlight ? Colors.green.shade700 : Colors.grey.shade700,
          ),
        ),
        Text(
          _currencyFormat.format(amount.round()),
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: isTotal
                ? Theme.of(context).colorScheme.primary
                : isHighlight
                    ? Colors.green.shade700
                    : null,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Colors.grey.shade700,
      ),
    );
  }

  Future<void> _openAccountPicker() async {
    final selected = await showDialog<Account>(
      context: context,
      builder: (context) {
        List<Account> filtered = List.from(_expenseAccounts);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Container(
                width: 480,
                constraints: const BoxConstraints(maxHeight: 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Seleccionar cuenta',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: 'Buscar por código o nombre...',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (term) {
                              final lower = term.toLowerCase();
                              setDialogState(() {
                                filtered = _expenseAccounts
                                    .where((a) =>
                                        a.code.toLowerCase().contains(lower) ||
                                        a.name.toLowerCase().contains(lower))
                                    .toList();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: Text('Sin resultados')),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final account = filtered[index];
                                return ListTile(
                                  dense: true,
                                  title:
                                      Text('${account.code} - ${account.name}'),
                                  subtitle: Text(account.category.displayName,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500)),
                                  onTap: () => Navigator.pop(context, account),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() => _selectedAccount = selected);
    }
  }

  Future<void> _openSupplierPicker() async {
    final selected = await showModalBottomSheet<shared_supplier.Supplier>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SupplierPickerSheet(
        suppliers: _suppliers,
        onCreateSupplier: _createQuickSupplier,
      ),
    );

    if (selected != null && mounted) {
      setState(() => _selectedSupplier = selected);
    }
  }

  Future<shared_supplier.Supplier?> _createQuickSupplier(String name) async {
    if (name.trim().isEmpty) return null;
    try {
      final supplier = await _purchaseService.createSupplier(name.trim());
      _suppliers = [..._suppliers, supplier];
      return supplier;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear proveedor: $e')),
      );
      return null;
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedAccount?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una cuenta de gastos')),
      );
      return;
    }

    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona el método de pago')),
      );
      return;
    }

    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No se pudo obtener el tenant')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final net = _netAmount;
      final tax = _ivaAmount;
      final total = _totalPaid;
      final taxRate = _hasIva ? 19.0 : 0.0;
      final hasExplicitPayments = _existingExpense?.payments.isNotEmpty == true;
      final effectivePostedAt = _existingExpense?.postedAt ?? _date;
      final effectivePaidAt =
          hasExplicitPayments ? (_existingExpense?.paidAt ?? _date) : _date;

      // For new expenses, generate the number now (increments counter)
      // For existing expenses, use what's already there
      String expenseNumber;
      if (widget.expenseId == null) {
        expenseNumber = await _generateExpenseNumber();
      } else {
        expenseNumber = _expenseNumberController.text;
      }

      final expense = Expense(
        id: _existingExpense?.id,
        tenantId: tenantId,
        expenseNumber: expenseNumber,
        supplierId: _selectedSupplier?.id,
        supplierName: _selectedSupplier?.name,
        supplierRut: _selectedSupplier?.rut,
        documentType: _documentType,
        documentNumber: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        issueDate: _date,
        currency: 'CLP',
        exchangeRate: 1,
        postingStatus: ExpensePostingStatus.posted,
        paymentStatus: ExpensePaymentStatus.paid,
        subtotal: net,
        taxAmount: tax,
        totalAmount: total,
        amountPaid: total,
        balance: 0,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        approvalStatus: ExpenseApprovalStatus.approved,
        postedAt: effectivePostedAt,
        paidAt: effectivePaidAt,
        paymentAccountId: _selectedPaymentMethod!.accountId,
        paymentMethodId: _selectedPaymentMethod!.id,
        createdAt: _existingExpense?.createdAt,
        updatedAt: DateTime.now(),
        lines: [
          ExpenseLine(
            id: _existingExpense?.lines.isNotEmpty == true
                ? _existingExpense!.lines.first.id
                : null,
            tenantId: tenantId,
            expenseId: _existingExpense?.id,
            lineIndex: 0,
            accountId: _selectedAccount!.id!,
            accountCode: _selectedAccount!.code,
            accountName: _selectedAccount!.name,
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            quantity: 1,
            unitPrice: net,
            subtotal: net,
            taxRate: taxRate,
            taxAmount: tax,
            total: total,
          ),
        ],
      );

      await _expenseService.saveExpense(expense);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.expenseId == null
                  ? 'Gasto registrado correctamente'
                  : 'Gasto actualizado',
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  double _parseAmount(String? text) {
    if (text == null || text.isEmpty) return 0;
    final normalized = text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  String _formatNumber(double value) {
    return NumberFormat('#,##0', 'es_CL').format(value.round());
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
}

/// Bottom sheet for selecting or creating a supplier
class _SupplierPickerSheet extends StatefulWidget {
  final List<shared_supplier.Supplier> suppliers;
  final Future<shared_supplier.Supplier?> Function(String) onCreateSupplier;

  const _SupplierPickerSheet({
    required this.suppliers,
    required this.onCreateSupplier,
  });

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newSupplierController = TextEditingController();
  late List<shared_supplier.Supplier> _filtered;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _filtered = widget.suppliers;
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newSupplierController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.suppliers.where((s) {
        return s.name.toLowerCase().contains(query) ||
            (s.rut?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.85,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        builder: (context, controller) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Seleccionar proveedor',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey.shade100,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Search
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre o RUT...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Quick create
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newSupplierController,
                              decoration: InputDecoration(
                                hintText: 'Crear nuevo proveedor...',
                                prefixIcon: const Icon(Icons.add),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade100,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _isCreating
                                ? null
                                : () async {
                                    final name =
                                        _newSupplierController.text.trim();
                                    if (name.isEmpty) return;
                                    setState(() => _isCreating = true);
                                    final created =
                                        await widget.onCreateSupplier(name);
                                    setState(() => _isCreating = false);
                                    if (created != null && mounted) {
                                      Navigator.pop(context, created);
                                    }
                                  },
                            child: _isCreating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Crear'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                // List
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.store_outlined,
                                  size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                'No se encontraron proveedores',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: controller,
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 72,
                            color: Colors.grey.shade200,
                          ),
                          itemBuilder: (context, index) {
                            final supplier = _filtered[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.grey.shade100,
                                child: Icon(Icons.store_outlined,
                                    color: Colors.grey.shade600),
                              ),
                              title: Text(
                                supplier.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              subtitle: supplier.rut != null
                                  ? Text(
                                      'RUT: ${ChileanUtils.formatRut(supplier.rut!)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    )
                                  : null,
                              trailing: Icon(Icons.chevron_right,
                                  color: Colors.grey.shade400),
                              onTap: () => Navigator.pop(context, supplier),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
