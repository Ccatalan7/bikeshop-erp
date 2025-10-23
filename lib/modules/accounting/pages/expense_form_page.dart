import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../accounting/models/account.dart';
import '../../accounting/services/accounting_service.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/expense_line.dart';
import '../services/expense_service.dart';

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

  Expense? _existingExpense;
  List<ExpenseCategory> _categories = const [];
  List<Account> _accounts = const [];

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  final TextEditingController _expenseNumberController =
      TextEditingController();
  final TextEditingController _supplierNameController =
      TextEditingController();
  final TextEditingController _supplierRutController = TextEditingController();
  final TextEditingController _documentNumberController =
      TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _paymentTermsController =
      TextEditingController();
  final TextEditingController _exchangeRateController =
      TextEditingController(text: '1');
  final TextEditingController _netAmountController = TextEditingController();
  final TextEditingController _taxRateController =
      TextEditingController(text: '19');
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _lineDescriptionController =
      TextEditingController();

  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;
  ExpenseDocumentType _documentType = ExpenseDocumentType.invoice;
  String? _selectedCategoryId;
  Account? _selectedAccount;

  double _subtotal = 0;
  double _taxAmount = 0;
  double _total = 0;
  final NumberFormat _currencyFormat = ChileanUtils.currencyFormat;

  @override
  void initState() {
    super.initState();
    _expenseService = context.read<ExpenseService>();
    _accountingService = context.read<AccountingService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final categoriesFuture =
          _expenseService.fetchCategories(forceRefresh: true);
      final accountsFuture = _accountingService.getAccounts();
      final expenseFuture = widget.expenseId == null
          ? Future<Expense?>.value()
          : _expenseService.getExpense(widget.expenseId!, forceRefresh: true);

      final results = await Future.wait([
        categoriesFuture,
        accountsFuture,
        expenseFuture,
      ]);

      final categories = results[0] as List<ExpenseCategory>;
      final accounts = results[1] as List<Account>;
      final expense = results[2] as Expense?;

      _categories = categories;
      _accounts = accounts;

      if (expense != null) {
        _existingExpense = expense;
        _expenseNumberController.text = expense.expenseNumber;
        _supplierNameController.text = expense.supplierName ?? '';
        _supplierRutController.text = expense.supplierRut ?? '';
        _documentNumberController.text = expense.documentNumber ?? '';
        _referenceController.text = expense.reference ?? '';
        _notesController.text = expense.notes ?? '';
        _paymentTermsController.text = expense.paymentTerms ?? '';
        _exchangeRateController.text =
            (expense.exchangeRate).toStringAsFixed(2);
        _netAmountController.text = _formatNumber(expense.subtotal);
        _taxRateController.text =
            expense.lines.isNotEmpty ? expense.lines.first.taxRate.toString() : '19';
        _lineDescriptionController.text =
            expense.lines.isNotEmpty ? (expense.lines.first.description ?? '') : '';
        _issueDate = expense.issueDate;
        _dueDate = expense.dueDate;
        _documentType = expense.documentType;
        _selectedCategoryId = expense.categoryId;
        _subtotal = expense.subtotal;
        _taxAmount = expense.taxAmount;
        _total = expense.totalAmount;

        if (expense.lines.isNotEmpty) {
          final firstLine = expense.lines.first;
          _selectedAccount = _accounts.firstWhere(
            (account) => account.id == firstLine.accountId,
            orElse: () => _accounts.firstWhere(
              (account) => account.code == firstLine.accountCode,
              orElse: () => accounts.isNotEmpty ? accounts.first : accountFallback(firstLine),
            ),
          );
          if (_selectedAccount != null) {
            _accountController.text =
                '${_selectedAccount!.code} - ${_selectedAccount!.name}';
          }
        }
      } else {
        _subtotal = 0;
        _taxAmount = 0;
        _total = 0;
      }

      if (_selectedAccount == null && _accounts.isNotEmpty) {
        _selectedAccount = _accounts.firstWhere(
          (account) => account.type == AccountType.expense,
          orElse: () => _accounts.first,
        );
        _accountController.text =
            '${_selectedAccount!.code} - ${_selectedAccount!.name}';
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Account accountFallback(ExpenseLine line) {
    return Account(
      id: line.accountId,
      code: line.accountCode,
      name: line.accountName,
      type: AccountType.expense,
      category: AccountCategory.operatingExpense,
    );
  }

  @override
  void dispose() {
    _expenseNumberController.dispose();
    _supplierNameController.dispose();
    _supplierRutController.dispose();
    _documentNumberController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _paymentTermsController.dispose();
    _exchangeRateController.dispose();
    _netAmountController.dispose();
    _taxRateController.dispose();
    _accountController.dispose();
    _lineDescriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.expenseId == null ? 'Nuevo gasto' : 'Editar gasto';

    return MainLayout(
      title: title,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
          Text('No se pudo cargar el formulario'),
          const SizedBox(height: 8),
          Text(_error ?? 'Error desconocido'),
          const SizedBox(height: 16),
          AppButton(
            text: 'Reintentar',
            icon: Icons.refresh,
            onPressed: _loadData,
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderActions(context),
            const SizedBox(height: 24),
            _buildGeneralSection(context),
            const SizedBox(height: 24),
            _buildAmountsSection(context),
            const SizedBox(height: 24),
            _buildAccountingSection(context),
            const SizedBox(height: 24),
            _buildNotesSection(context),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                text: widget.expenseId == null ? 'Crear gasto' : 'Guardar cambios',
                icon: Icons.save_outlined,
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _handleSave,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderActions(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: _isSaving ? null : () => context.pop(false),
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 8),
        Text(
          widget.expenseId == null ? 'Registrar nuevo gasto' : 'Actualizar gasto',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Recalcular totales',
          onPressed: _recalculateTotals,
          icon: const Icon(Icons.calculate_outlined),
        ),
      ],
    );
  }

  Widget _buildGeneralSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Información general',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    controller: _expenseNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Número de gasto *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa el número de gasto';
                      }
                      return null;
                    },
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<ExpenseDocumentType>(
                    value: _documentType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de documento',
                      border: OutlineInputBorder(),
                    ),
                    items: ExpenseDocumentType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(_documentTypeLabel(type)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _documentType = value);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    controller: _documentNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Número de documento',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sin categoría')),
                      ..._categories.map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _selectedCategoryId = value;
                    }),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    controller: _supplierNameController,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    controller: _supplierRutController,
                    decoration: const InputDecoration(
                      labelText: 'RUT proveedor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: _buildDateField(
                    context,
                    label: 'Fecha de emisión *',
                    value: _issueDate,
                    onChanged: (date) => setState(() => _issueDate = date),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: _buildDateField(
                    context,
                    label: 'Fecha de vencimiento',
                    value: _dueDate,
                    onChanged: (date) => setState(() => _dueDate = date),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    controller: _paymentTermsController,
                    decoration: const InputDecoration(
                      labelText: 'Condiciones de pago',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    controller: _exchangeRateController,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de cambio',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField(
    BuildContext context, {
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onChanged,
  }) {
    final display = value == null
        ? 'Seleccionar'
        : ChileanUtils.formatDate(value);

    return OutlinedButton.icon(
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      icon: const Icon(Icons.calendar_today_outlined),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text('$label: $display'),
      ),
    );
  }

  Widget _buildAmountsSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Montos',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    controller: _netAmountController,
                    decoration: const InputDecoration(
                      labelText: 'Monto neto *',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (_parseDouble(value) <= 0) {
                        return 'Ingresa un monto válido';
                      }
                      return null;
                    },
                    onChanged: (_) => _recalculateTotals(),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    controller: _taxRateController,
                    decoration: const InputDecoration(
                      labelText: 'IVA %',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _recalculateTotals(),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    controller: _lineDescriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción partida contable',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _amountSummaryChip(
                  context,
                  label: 'Subtotal',
                  amount: _subtotal,
                  color: Colors.blueGrey.shade600,
                ),
                _amountSummaryChip(
                  context,
                  label: 'IVA',
                  amount: _taxAmount,
                  color: Colors.orange.shade600,
                ),
                _amountSummaryChip(
                  context,
                  label: 'Total',
                  amount: _total,
                  color: Colors.green.shade700,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountSummaryChip(
    BuildContext context, {
    required String label,
    required double amount,
    required Color color,
  }) {
    final background = Color.lerp(color, Colors.white, 0.85)!;
    return Chip(
      backgroundColor: background,
      avatar: CircleAvatar(
        backgroundColor: color,
        child: const Icon(Icons.calculate_outlined, color: Colors.white),
      ),
      label: Text('$label: ${_currencyFormat.format(amount)}'),
    );
  }

  Widget _buildAccountingSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contabilidad',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 320,
              child: TextFormField(
                controller: _accountController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Cuenta contable *',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.search),
                ),
                onTap: _accounts.isEmpty ? null : _openAccountPicker,
                validator: (_) {
                  if (_selectedAccount == null) {
                    return 'Selecciona la cuenta contable';
                  }
                  if (_selectedAccount?.id == null) {
                    return 'Cuenta contable inválida';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notas adicionales',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Referencia',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notas',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAccountPicker() async {
    final selected = await showDialog<Account>(
      context: context,
      builder: (context) {
        List<Account> filtered = List<Account>.from(_accounts);
        return StatefulBuilder(
          builder: (context, setState) {
            void filter(String term) {
              final lower = term.toLowerCase();
              setState(() {
                filtered = _accounts
                    .where((account) =>
                        account.code.toLowerCase().contains(lower) ||
                        account.name.toLowerCase().contains(lower))
                    .toList();
              });
            }

            return AlertDialog(
              title: const Text('Seleccionar cuenta contable'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar por código o nombre',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: filter,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Sin resultados'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final account = filtered[index];
                                return ListTile(
                                  title: Text('${account.code} · ${account.name}'),
                                  subtitle: Text(account.type.displayName),
                                  onTap: () => Navigator.of(context).pop(account),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedAccount = selected;
        _accountController.text = '${selected.code} - ${selected.name}';
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedAccount?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una cuenta válida')), 
      );
      return;
    }

    final net = _parseDouble(_netAmountController.text);
    final taxRate = _parseDouble(_taxRateController.text);
    final taxAmount = net * (taxRate / 100);
    final total = net + taxAmount;
    final exchangeRate = _parseDouble(_exchangeRateController.text, fallback: 1);

    setState(() => _isSaving = true);

    try {
      final expense = Expense(
        id: _existingExpense?.id,
        expenseNumber: _expenseNumberController.text.trim(),
        categoryId: _selectedCategoryId,
        category: _existingExpense?.category,
        supplierId: _existingExpense?.supplierId,
        supplierName: _supplierNameController.text.trim().isEmpty
            ? null
            : _supplierNameController.text.trim(),
        supplierRut: _supplierRutController.text.trim().isEmpty
            ? null
            : _supplierRutController.text.trim(),
        documentType: _documentType,
        documentNumber: _documentNumberController.text.trim().isEmpty
            ? null
            : _documentNumberController.text.trim(),
        issueDate: _issueDate,
        dueDate: _dueDate,
        paymentTerms: _paymentTermsController.text.trim().isEmpty
            ? null
            : _paymentTermsController.text.trim(),
        currency: _existingExpense?.currency ?? 'CLP',
        exchangeRate: exchangeRate,
        postingStatus:
            _existingExpense?.postingStatus ?? ExpensePostingStatus.draft,
        paymentStatus:
            _existingExpense?.paymentStatus ?? ExpensePaymentStatus.pending,
        subtotal: net,
        taxAmount: taxAmount,
        totalAmount: total,
        amountPaid: _existingExpense?.amountPaid ?? 0,
        balance: (_existingExpense?.amountPaid ?? 0) >= total
            ? 0
            : total - (_existingExpense?.amountPaid ?? 0),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        approvalStatus:
            _existingExpense?.approvalStatus ?? ExpenseApprovalStatus.pending,
        approvedBy: _existingExpense?.approvedBy,
        approvedAt: _existingExpense?.approvedAt,
        postedAt: _existingExpense?.postedAt,
        paidAt: _existingExpense?.paidAt,
        liabilityAccountId: _existingExpense?.liabilityAccountId,
        paymentAccountId: _existingExpense?.paymentAccountId,
        paymentMethodId: _existingExpense?.paymentMethodId,
  tags: List<String>.from(_existingExpense?.tags ?? const []),
        createdBy: _existingExpense?.createdBy,
        createdAt: _existingExpense?.createdAt,
        updatedAt: DateTime.now(),
        lines: [
          ExpenseLine(
            id: _existingExpense != null && _existingExpense!.lines.isNotEmpty
                ? _existingExpense!.lines.first.id
                : null,
            expenseId: _existingExpense?.id,
            lineIndex: 0,
            accountId: _selectedAccount!.id ?? '',
            accountCode: _selectedAccount!.code,
            accountName: _selectedAccount!.name,
            description: _lineDescriptionController.text.trim().isEmpty
                ? null
                : _lineDescriptionController.text.trim(),
            quantity: 1,
            unitPrice: net,
            subtotal: net,
            taxRate: taxRate,
            taxAmount: taxAmount,
            total: total,
          ),
        ],
        payments: _existingExpense?.payments ?? const [],
        attachments: _existingExpense?.attachments ?? const [],
      );

      await _expenseService.saveExpense(expense);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.expenseId == null
                  ? 'Gasto creado correctamente'
                  : 'Gasto actualizado correctamente',
            ),
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el gasto: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _recalculateTotals() {
    final net = _parseDouble(_netAmountController.text);
    final taxRate = _parseDouble(_taxRateController.text);
    final tax = net * (taxRate / 100);
    setState(() {
      _subtotal = net;
      _taxAmount = tax;
      _total = net + tax;
    });
  }

  double _parseDouble(String? text, {double fallback = 0}) {
    if (text == null) return fallback;
    final normalized = text.replaceAll('.', '').replaceAll(',', '.');
    final value = double.tryParse(normalized.trim());
    return value ?? fallback;
  }

  String _formatNumber(double value) {
    final formatter = NumberFormat('#,##0.##', 'es_CL');
    return formatter.format(value);
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
