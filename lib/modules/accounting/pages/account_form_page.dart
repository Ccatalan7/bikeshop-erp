import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/app_button.dart';
import '../models/account.dart';
import '../services/accounting_service.dart';

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
      
      // Load all accounts for parent selection
      _allAccounts = await accountingService.getAccounts();

      // If editing, load existing account
      if (widget.accountId != null) {
        _existingAccount = await accountingService.getAccountById(widget.accountId!);
        
        if (_existingAccount != null) {
          _codeController.text = _existingAccount!.code;
          _nameController.text = _existingAccount!.name;
          _descriptionController.text = _existingAccount!.description ?? '';
          _selectedType = _existingAccount!.type;
          _selectedCategory = _existingAccount!.category;
          _selectedParentId = _existingAccount!.parentId;
          _isActive = _existingAccount!.isActive;
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
        ];
      case AccountType.tax:
        return [
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

      final account = Account(
        id: _existingAccount?.id,
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
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
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
            ),
            
            // Form Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
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
                                      final validCategories = _getCategoriesForType(value);
                                      _selectedCategory = validCategories.first;
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
                                items: _getCategoriesForType(_selectedType).map((category) {
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

                              // Parent Account Dropdown (optional)
                              DropdownButtonFormField<String?>(
                                value: _selectedParentId,
                                decoration: const InputDecoration(
                                  labelText: 'Cuenta Padre (Opcional)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.account_tree),
                                  helperText: 'Seleccione una cuenta padre si aplica',
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Sin cuenta padre'),
                                  ),
                                  ..._allAccounts
                                      .where((a) => a.id != widget.accountId) // Don't allow self as parent
                                      .map((account) {
                                    return DropdownMenuItem<String?>(
                                      value: account.id,
                                      child: Text('${account.code} - ${account.name}'),
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
                                  hintText: 'Información adicional sobre la cuenta',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.description),
                                ),
                                maxLines: 3,
                                textCapitalization: TextCapitalization.sentences,
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.info, color: Colors.blue.shade700),
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