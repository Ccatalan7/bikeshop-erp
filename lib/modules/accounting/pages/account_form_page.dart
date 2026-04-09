import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/tenant_service.dart';
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
  bool _isApplyingSuggestedCode = false;
  bool _hasManualCodeOverride = false;
  String? _lastSuggestedCode;

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
        }
      } else {
        _applySuggestedAccountCode(force: true);
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
          // Tax categories can be used with expense type
          AccountCategory.taxPayable,
          AccountCategory.taxReceivable,
          AccountCategory.taxExpense,
        ];
    }
  }

  String _normalizeAccountCode(String value) => value.trim().toUpperCase();

  int? _parseAccountCodeValue(String code) => int.tryParse(code.trim());

  int _defaultBaseCodeForType(AccountType type) {
    switch (type) {
      case AccountType.asset:
        return 1000;
      case AccountType.liability:
        return 2000;
      case AccountType.equity:
        return 3000;
      case AccountType.income:
        return 4000;
      case AccountType.expense:
        return 5000;
    }
  }

  String _suggestNextAccountCode() {
    int? maxCode;

    for (final account in _allAccounts) {
      if (account.id == _existingAccount?.id) {
        continue;
      }

      if (account.type == _selectedType &&
          account.category == _selectedCategory) {
        final parsedCode = _parseAccountCodeValue(account.code);
        if (parsedCode != null && (maxCode == null || parsedCode > maxCode)) {
          maxCode = parsedCode;
        }
      }
    }

    if (maxCode == null) {
      for (final account in _allAccounts) {
        if (account.id == _existingAccount?.id) {
          continue;
        }

        if (account.type == _selectedType) {
          final parsedCode = _parseAccountCodeValue(account.code);
          if (parsedCode != null && (maxCode == null || parsedCode > maxCode)) {
            maxCode = parsedCode;
          }
        }
      }
    }

    final nextCode =
        (maxCode ?? _defaultBaseCodeForType(_selectedType) - 1) + 1;
    return nextCode.toString();
  }

  void _applySuggestedAccountCode({bool force = false}) {
    if (widget.accountId != null) {
      return;
    }

    final currentCode = _codeController.text.trim();
    final canReplace = force ||
        !_hasManualCodeOverride ||
        currentCode.isEmpty ||
        currentCode == (_lastSuggestedCode ?? '');

    if (!canReplace) {
      return;
    }

    final suggestedCode = _suggestNextAccountCode();
    _isApplyingSuggestedCode = true;
    _lastSuggestedCode = suggestedCode;
    _codeController.value = _codeController.value.copyWith(
      text: suggestedCode,
      selection: TextSelection.collapsed(offset: suggestedCode.length),
      composing: TextRange.empty,
    );
    _hasManualCodeOverride = false;
    _isApplyingSuggestedCode = false;
  }

  void _handleCodeChanged(String value) {
    if (widget.accountId != null || _isApplyingSuggestedCode) {
      return;
    }

    final trimmedValue = value.trim();
    _hasManualCodeOverride =
        trimmedValue.isNotEmpty && trimmedValue != (_lastSuggestedCode ?? '');
  }

  Account? _findDuplicateAccountByCode(String rawCode) {
    final normalizedCode = _normalizeAccountCode(rawCode);
    if (normalizedCode.isEmpty) return null;

    for (final account in _allAccounts) {
      if (account.id == _existingAccount?.id) {
        continue;
      }

      if (_normalizeAccountCode(account.code) == normalizedCode) {
        return account;
      }
    }

    return null;
  }

  String? _validateAccountCode(String? value) {
    final trimmedValue = value?.trim() ?? '';

    if (trimmedValue.isEmpty) {
      return 'El código es obligatorio';
    }

    if (trimmedValue.length < 2) {
      return 'El código debe tener al menos 2 caracteres';
    }

    final duplicateAccount = _findDuplicateAccountByCode(trimmedValue);
    if (duplicateAccount != null) {
      return 'El código ${duplicateAccount.code} ya existe en ${duplicateAccount.name}';
    }

    return null;
  }

  bool _isDuplicateAccountCodeError(Object error) {
    if (error is PostgrestException) {
      final details = error.details?.toString() ?? '';
      return error.code == '23505' &&
          (error.message.contains('accounts_tenant_id_code_key') ||
              details.contains('(tenant_id, code)'));
    }

    final message = error.toString();
    return message.contains('accounts_tenant_id_code_key') ||
        message.contains('duplicate key value violates unique constraint');
  }

  String _buildSaveErrorMessage(Object error) {
    if (_isDuplicateAccountCodeError(error)) {
      final duplicatedCode = _codeController.text.trim();
      return 'Ya existe una cuenta con el código $duplicatedCode. Usa un código distinto.';
    }

    if (error is PostgrestException && error.message.isNotEmpty) {
      return 'Error al guardar: ${error.message}';
    }

    return 'Error al guardar: $error';
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final accountingService = context.read<AccountingService>();
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
            content: Text(_buildSaveErrorMessage(e)),
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
                                decoration: InputDecoration(
                                  labelText: 'Código *',
                                  hintText: 'Ej: 1155',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.numbers),
                                  helperText: widget.accountId == null
                                      ? 'Código sugerido según la clasificación. Puedes cambiarlo.'
                                      : 'Código único de la cuenta',
                                ),
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                validator: _validateAccountCode,
                                onChanged: _handleCodeChanged,
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
                                  helperText:
                                      'Nombre con el que la cuenta aparecerá en el plan de cuentas',
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

                              Card(
                                color: Colors.blue.shade50,
                                child: const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.info_outline),
                                          SizedBox(width: 8),
                                          Text(
                                            'Cómo se organiza una cuenta',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        '• Naturaleza contable: define si la cuenta es Activo, Pasivo, Patrimonio, Ingreso o Gasto.\n'
                                        '• Categoría principal: ubica la cuenta dentro del plan contable.\n'
                                        '• Cuenta padre: solo crea una jerarquía entre cuentas. Si la dejas vacía, la cuenta queda independiente.',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              Text(
                                'Clasificación contable',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Define qué representa la cuenta dentro del plan contable.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 16),

                              // Type Dropdown
                              DropdownButtonFormField<AccountType>(
                                initialValue: _selectedType,
                                decoration: const InputDecoration(
                                  labelText: 'Naturaleza contable *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.category),
                                  helperText:
                                      'Impacto principal de la cuenta en balance o resultados',
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
                                      _applySuggestedAccountCode();
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              // Category Dropdown
                              DropdownButtonFormField<AccountCategory>(
                                initialValue: _selectedCategory,
                                decoration: const InputDecoration(
                                  labelText: 'Categoría principal *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.folder),
                                  helperText:
                                      'Grupo contable al que pertenecerá esta cuenta dentro del plan',
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
                                    setState(() {
                                      _selectedCategory = value;
                                      _applySuggestedAccountCode();
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              if (_selectedType == AccountType.expense) ...[
                                Card(
                                  color: Colors.amber.shade50,
                                  child: const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.rule_folder_outlined),
                                            SizedBox(width: 8),
                                            Text(
                                              'Categorías de gasto',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Las categorías de gasto se administran por separado en el módulo de Gastos. No crean relaciones contables entre cuentas. Si quieres agrupar esta cuenta bajo otra, usa solamente el campo Cuenta padre.',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],

                              Text(
                                'Jerarquía y uso',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Opcionalmente puedes agrupar la cuenta bajo una cuenta padre.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 16),

                              // Parent Account Dropdown (optional)
                              DropdownButtonFormField<String?>(
                                initialValue: _selectedParentId,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Cuenta padre (jerarquía opcional)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.account_tree),
                                  helperText:
                                      'Solo úsala si esta cuenta depende jerárquicamente de otra. Si la dejas vacía, la cuenta será independiente.',
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
                                  }),
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
