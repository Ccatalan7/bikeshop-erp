import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/account.dart';
import '../models/expense_category.dart';
import '../services/accounting_service.dart';
import '../services/expense_service.dart';

class AccountFormPage extends StatefulWidget {
  final String? accountId;

  const AccountFormPage({super.key, this.accountId});

  @override
  State<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends State<AccountFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isSaving = false;
  bool _isLoading = true;
  AccountType _selectedType = AccountType.asset;
  AccountCategory _selectedCategory = AccountCategory.currentAsset;
  String? _selectedParentId;
  bool _isActive = true;
  Account? _existingAccount;
  List<Account> _allAccounts = [];

  // Expense category mapping (uses expense_categories.default_account_id)
  List<ExpenseCategory> _expenseCategories = const [];
  String? _selectedExpenseCategoryId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final accountingService = context.read<AccountingService>();
      final expenseService = context.read<ExpenseService>();

      // Load all accounts for parent selection
      _allAccounts = await accountingService.getAccounts();

      // Load expense categories for mapping
      _expenseCategories = await expenseService.fetchCategories();

      // If editing, load existing account
      if (widget.accountId != null) {
        _existingAccount =
            await accountingService.getAccountById(widget.accountId!);

        if (_existingAccount != null) {
          _codeController.text = _existingAccount!.code;
          _nameController.text = _existingAccount!.name;
          _descriptionController.text = _existingAccount!.description ?? '';
          _selectedType = _existingAccount!.type;
          _selectedCategory = _existingAccount!.category;
          _selectedParentId = _existingAccount!.parentId;
          _isActive = _existingAccount!.isActive;

          // Preselect the category linked to this account (if any)
          final linkedCategory = _expenseCategories
              .where((c) => c.defaultAccountId == _existingAccount!.id)
              .cast<ExpenseCategory?>()
              .firstWhere(
                (c) => c != null,
                orElse: () => null,
              );
          _selectedExpenseCategoryId = linkedCategory?.id;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreateExpenseCategoryDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isSubmitting = false;

    final created = await showDialog<ExpenseCategory>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nueva categoría de gasto'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final description = descController.text.trim();

                          if (name.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('El nombre es obligatorio'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSubmitting = true);
                          try {
                            final expenseService = context.read<ExpenseService>();
                            final createdCategory = await expenseService.saveCategory(
                              ExpenseCategory(
                                id: '',
                                name: name,
                                description: description.isEmpty ? null : description,
                                // If we're editing an existing account, we can bind immediately.
                                // If it's a new account, we will bind after saving the account.
                                defaultAccountId: _existingAccount?.id,
                              ),
                            );
                            if (context.mounted) {
                              Navigator.pop(context, createdCategory);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('No se pudo crear: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              setDialogState(() => isSubmitting = false);
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descController.dispose();

    if (created == null) return;

    // Refresh list + select the created category
    if (!mounted) return;
    final expenseService = context.read<ExpenseService>();
    final refreshed = await expenseService.fetchCategories(forceRefresh: true);
    setState(() {
      _expenseCategories = refreshed;
      _selectedExpenseCategoryId = created.id;
    });
  }

  Future<void> _applyExpenseCategoryMapping({
    required String accountId,
  }) async {
    // Only relevant for expense accounts
    if (_selectedType != AccountType.expense) return;

    final expenseService = context.read<ExpenseService>();
    final categories = await expenseService.fetchCategories(forceRefresh: true);

    final previouslyLinked = categories
        .where((c) => c.defaultAccountId == accountId)
        .toList(growable: false);

    // Clear previous link(s) if they are not the selected one
    for (final c in previouslyLinked) {
      if (_selectedExpenseCategoryId == null || c.id != _selectedExpenseCategoryId) {
        await expenseService.saveCategory(c.copyWith(defaultAccountId: null));
      }
    }

    if (_selectedExpenseCategoryId == null) return;
    final selected = categories.firstWhere(
      (c) => c.id == _selectedExpenseCategoryId,
      orElse: () => const ExpenseCategory(id: '', name: ''),
    );
    if (selected.id.isEmpty) return;

    if (selected.defaultAccountId != accountId) {
      await expenseService.saveCategory(selected.copyWith(defaultAccountId: accountId));
    }
  }

  List<AccountCategory> _getCategoriesForType(AccountType type) {
    switch (type) {
      case AccountType.asset:
        return [
          AccountCategory.currentAsset,
          AccountCategory.fixedAsset,
          AccountCategory.otherAsset,
        ];
      case AccountType.liability:
        return [
          AccountCategory.currentLiability,
          AccountCategory.longTermLiability,
        ];
      case AccountType.equity:
        return [
          AccountCategory.capital,
          AccountCategory.retainedEarnings,
        ];
      case AccountType.income:
        return [
          AccountCategory.operatingIncome,
          AccountCategory.nonOperatingIncome,
        ];
      case AccountType.expense:
        return [
          AccountCategory.costOfGoodsSold,
          AccountCategory.operatingExpense,
          AccountCategory.financialExpense,
          // Tax categories can be used with expense type
          AccountCategory.taxPayable,
          AccountCategory.taxReceivable,
          AccountCategory.taxExpense,
        ];
    }
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final accountingService = context.read<AccountingService>();
      final expenseService = context.read<ExpenseService>();
      final tenantId = await TenantService().getTenantId();

      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      final account = Account(
        id: _existingAccount?.id,
        tenantId: tenantId,
        code: _codeController.text.trim(),
        name: _nameController.text.trim(),
        type: _selectedType,
        category: _selectedCategory,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        parentId: _selectedParentId,
        isActive: _isActive,
        createdAt: _existingAccount?.createdAt,
        updatedAt: DateTime.now(),
      );

      if (widget.accountId != null) {
        await accountingService.updateAccount(account);
      } else {
        await accountingService.createAccount(account);
      }

      // Resolve saved account id (createAccount() doesn't return it)
      final savedAccount = widget.accountId != null
          ? await accountingService.getAccountById(widget.accountId!)
          : await accountingService.getAccountByCode(account.code);
      final savedAccountId = savedAccount?.id;

      if (savedAccountId != null) {
        // Ensure categories cache is fresh before applying mapping
        await expenseService.fetchCategories(forceRefresh: true);
        await _applyExpenseCategoryMapping(accountId: savedAccountId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.accountId != null
                  ? 'Cuenta actualizada exitosamente'
                  : 'Cuenta creada exitosamente',
            ),
            backgroundColor: Colors.green,
          ),
        );
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;

                if (isMobile) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => context.pop(),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.accountId != null
                                    ? 'Editar Cuenta'
                                    : 'Nueva Cuenta',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        AppButton(
                          text: 'Guardar',
                          icon: Icons.save,
                          onPressed: _saveAccount,
                          isLoading: _isSaving,
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.accountId != null
                              ? 'Editar Cuenta'
                              : 'Nueva Cuenta',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      AppButton(
                        text: 'Guardar',
                        icon: Icons.save,
                        onPressed: _saveAccount,
                        isLoading: _isSaving,
                      ),
                    ],
                  ),
                );
              },
            ),

            // Form Content
            Expanded(
              child: _isLoading
                  ? const Center(child: BrandedLoading())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Code Field
                              TextFormField(
                                controller: _codeController,
                                decoration: const InputDecoration(
                                  labelText: 'Código *',
                                  hintText: 'Ej: 1155',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.numbers),
                                  helperText: 'Código único de la cuenta',
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'El código es obligatorio';
                                  }
                                  if (value.trim().length < 2) {
                                    return 'El código debe tener al menos 2 caracteres';
                                  }
                                  return null;
                                },
                                textCapitalization: TextCapitalization.none,
                              ),
                              const SizedBox(height: 16),

                              // Name Field
                              TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre *',
                                  hintText: 'Ej: Inventario en Tránsito',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.label),
                                  helperText: 'Nombre descriptivo de la cuenta',
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'El nombre es obligatorio';
                                  }
                                  if (value.trim().length < 3) {
                                    return 'El nombre debe tener al menos 3 caracteres';
                                  }
                                  return null;
                                },
                                textCapitalization: TextCapitalization.words,
                              ),
                              const SizedBox(height: 16),

                              // Type Dropdown
                              DropdownButtonFormField<AccountType>(
                                value: _selectedType,
                                decoration: const InputDecoration(
                                  labelText: 'Tipo *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.category),
                                  helperText: 'Tipo de cuenta contable',
                                ),
                                items: AccountType.values.map((type) {
                                  return DropdownMenuItem(
                                    value: type,
                                    child: Text(type.displayName),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedType = value;
                                      // Reset category to first valid one
                                      final validCategories =
                                          _getCategoriesForType(value);
                                      _selectedCategory = validCategories.first;
                                      if (value != AccountType.expense) {
                                        _selectedExpenseCategoryId = null;
                                      }
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              // Category Dropdown
                              DropdownButtonFormField<AccountCategory>(
                                value: _selectedCategory,
                                decoration: const InputDecoration(
                                  labelText: 'Categoría *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.folder),
                                  helperText: 'Categoría específica',
                                ),
                                items: _getCategoriesForType(_selectedType)
                                    .map((category) {
                                  return DropdownMenuItem(
                                    value: category,
                                    child: Text(category.displayName),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _selectedCategory = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              // Expense Category Mapping (only for expense accounts)
                              if (_selectedType == AccountType.expense) ...[
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isNarrow = constraints.maxWidth < 520;
                                    final dropdown = DropdownButtonFormField<String?>(
                                      value: _selectedExpenseCategoryId,
                                      decoration: const InputDecoration(
                                        labelText: 'Categoría de gasto (opcional)',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.sell_outlined),
                                        helperText:
                                            'Se usa para auto-etiquetar gastos según la cuenta contable',
                                      ),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('Sin categoría'),
                                        ),
                                        ..._expenseCategories.map((c) {
                                          return DropdownMenuItem<String?>(
                                            value: c.id,
                                            child: Text(c.name),
                                          );
                                        }),
                                      ],
                                      onChanged: (value) {
                                        setState(() => _selectedExpenseCategoryId = value);
                                      },
                                    );

                                    final addButton = AppButton(
                                      text: 'Nueva categoría',
                                      icon: Icons.add,
                                      onPressed: _showCreateExpenseCategoryDialog,
                                      type: ButtonType.outline,
                                    );

                                    if (isNarrow) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          dropdown,
                                          const SizedBox(height: 12),
                                          addButton,
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: dropdown),
                                        const SizedBox(width: 12),
                                        SizedBox(width: 180, child: addButton),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Parent Account Dropdown (optional)
                              DropdownButtonFormField<String?>(
                                value: _selectedParentId,
                                decoration: const InputDecoration(
                                  labelText: 'Cuenta Padre (Opcional)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.account_tree),
                                  helperText:
                                      'Seleccione una cuenta padre si aplica',
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Sin cuenta padre'),
                                  ),
                                  ..._allAccounts
                                      .where((a) =>
                                          a.id !=
                                          widget
                                              .accountId) // Don't allow self as parent
                                      .map((account) {
                                    return DropdownMenuItem<String?>(
                                      value: account.id,
                                      child: Text(
                                          '${account.code} - ${account.name}'),
                                    );
                                  }).toList(),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedParentId = value);
                                },
                              ),
                              const SizedBox(height: 16),

                              // Description Field
                              TextFormField(
                                controller: _descriptionController,
                                decoration: const InputDecoration(
                                  labelText: 'Descripción (Opcional)',
                                  hintText:
                                      'Información adicional sobre la cuenta',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.description),
                                ),
                                maxLines: 3,
                                textCapitalization:
                                    TextCapitalization.sentences,
                              ),
                              const SizedBox(height: 16),

                              // Active Switch
                              SwitchListTile(
                                value: _isActive,
                                onChanged: (value) {
                                  setState(() => _isActive = value);
                                },
                                title: const Text('Cuenta Activa'),
                                subtitle: Text(
                                  _isActive
                                      ? 'La cuenta puede ser usada en transacciones'
                                      : 'La cuenta está desactivada',
                                ),
                                secondary: Icon(
                                  _isActive ? Icons.check_circle : Icons.cancel,
                                  color: _isActive ? Colors.green : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Info Card
                              Card(
                                color: Colors.blue.shade50,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.info,
                                              color: Colors.blue.shade700),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Información',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        '• El código debe ser único\n'
                                        '• Las cuentas pueden organizarse jerárquicamente\n'
                                        '• Las cuentas inactivas no aparecen en formularios\n'
                                        '• No se pueden eliminar cuentas con movimientos',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
