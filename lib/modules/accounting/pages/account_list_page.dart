import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/account.dart';
import '../services/accounting_service.dart';
import 'account_ledger_page.dart';

class AccountListPage extends StatefulWidget {
  const AccountListPage({super.key});

  @override
  State<AccountListPage> createState() => _AccountListPageState();
}

class _AccountListPageState extends State<AccountListPage> {
  late AccountingService _accountingService;
  List<Account> _accounts = [];
  List<Account> _filteredAccounts = [];
  bool _isLoading = true;
  String _searchTerm = '';
  AccountType? _selectedType;
  Account? _selectedAccount; // Added for split-pane view

  @override
  void initState() {
    super.initState();
    _accountingService = Provider.of<AccountingService>(context, listen: false);
    // Delay the load to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAccounts();
    });
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);

    try {
      final accounts = await _accountingService.getAccounts();

      setState(() {
        _accounts = accounts;
        _filteredAccounts = accounts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando cuentas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterAccounts() {
    setState(() {
      _filteredAccounts = _accounts.where((account) {
        final matchesSearch = _searchTerm.isEmpty ||
            account.code.toLowerCase().contains(_searchTerm.toLowerCase()) ||
            account.name.toLowerCase().contains(_searchTerm.toLowerCase()) ||
            (account.description
                    ?.toLowerCase()
                    .contains(_searchTerm.toLowerCase()) ??
                false);

        final matchesType =
            _selectedType == null || account.type == _selectedType;

        return matchesSearch && matchesType && account.isActive;
      }).toList();
    });
  }

  void _onSearchChanged(String value) {
    setState(() => _searchTerm = value);
    _filterAccounts();
  }

  void _onTypeFilterChanged(AccountType? type) {
    setState(() => _selectedType = type);
    _filterAccounts();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        // On mobile, if account selected, show full screen ledger
        if (isMobile && _selectedAccount != null) {
          return Scaffold(
            appBar: AppBar(
              title:
                  Text('${_selectedAccount!.code} - ${_selectedAccount!.name}'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedAccount = null),
              ),
            ),
            body: AccountLedgerPage(
              key: ValueKey(_selectedAccount!.id),
              account: _selectedAccount!,
              isEmbedded: false,
            ),
          );
        }

        // Desktop split-view or Mobile list view
        if (_selectedAccount != null && !isMobile) {
          return MainLayout(
            title: 'Plan de Cuentas',
            body: Row(
              children: [
                // Left: Accounts list (narrower)
                SizedBox(
                  width: 360,
                  child: Column(
                    children: [
                      // Back button
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          border: Border(
                            bottom: BorderSide(
                                color: Theme.of(context).dividerColor),
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () =>
                                  setState(() => _selectedAccount = null),
                              tooltip: 'Volver al listado',
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Volver al listado',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Original content (compact)
                      Expanded(
                        child: Column(
                          children: [
                            _buildSearchAndFilterBar(
                                isMobile: false), // Compact version
                            Expanded(child: _buildAccountsList()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Divider
                VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).dividerColor),
                // Right: Account ledger
                Expanded(
                  child: AccountLedgerPage(
                    key: ValueKey(_selectedAccount!.id),
                    account: _selectedAccount!,
                    isEmbedded: true,
                  ),
                ),
              ],
            ),
          );
        }

        // Normal full-width layout (List only)
        return MainLayout(
          title: 'Plan de Cuentas',
          body: Column(
            children: [
              _buildSearchAndFilterBar(isMobile: isMobile),
              Expanded(child: _buildAccountsList()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchAndFilterBar({required bool isMobile}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SearchWidget(
                  hintText: 'Buscar...',
                  onSearchChanged: _onSearchChanged,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountType?>(
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  value: _selectedType,
                  items: [
                    const DropdownMenuItem<AccountType?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ...AccountType.values.map(
                      (type) => DropdownMenuItem<AccountType?>(
                        value: type,
                        child: Text(type.displayName),
                      ),
                    ),
                  ],
                  onChanged: _onTypeFilterChanged,
                ),
                const SizedBox(height: 12),
                AppButton(
                  text: 'Nueva Cuenta',
                  onPressed: () => context.push('/accounting/accounts/new'),
                  icon: Icons.add,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SearchWidget(
                    hintText: 'Buscar por código, nombre o descripción...',
                    onSearchChanged: _onSearchChanged,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<AccountType?>(
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    value: _selectedType,
                    items: [
                      const DropdownMenuItem<AccountType?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      ...AccountType.values.map(
                        (type) => DropdownMenuItem<AccountType?>(
                          value: type,
                          child: Text(type.displayName),
                        ),
                      ),
                    ],
                    onChanged: _onTypeFilterChanged,
                  ),
                ),
                const SizedBox(width: 16),
                AppButton(
                  text: 'Nueva Cuenta',
                  onPressed: () => context.push('/accounting/accounts/new'),
                  icon: Icons.add,
                ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Total: ${_filteredAccounts.length} cuentas',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              if (_isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsList() {
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }

    if (_filteredAccounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance,
              size: 64,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty && _selectedType == null
                  ? 'No hay cuentas registradas'
                  : 'No se encontraron cuentas que coincidan con los filtros',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredAccounts.length,
      itemBuilder: (context, index) {
        final account = _filteredAccounts[index];
        final isSelected = _selectedAccount?.id == account.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : null,
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getTypeColor(account.type).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getTypeColor(account.type),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  account.code.substring(
                      0,
                      account.code.indexOf('.') != -1
                          ? account.code.indexOf('.')
                          : 1),
                  style: TextStyle(
                    color: _getTypeColor(account.type),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            title: Text(
              '${account.code} - ${account.name}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getTypeColor(account.type).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getTypeColor(account.type),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        account.type.displayName,
                        style: TextStyle(
                          color: _getTypeColor(account.type),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        account.category.displayName,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (account.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    account.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    context.push('/accounting/accounts/${account.id}/edit');
                    break;
                  case 'view':
                    _showAccountDetails(account);
                    break;
                  case 'delete':
                    _confirmDeleteAccount(account);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                    leading: Icon(Icons.visibility),
                    title: Text('Ver detalles'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text('Editar'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title:
                        Text('Eliminar', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            onTap: () => _showAccountDetails(account),
          ),
        );
      },
    );
  }

  Color _getTypeColor(AccountType type) {
    switch (type) {
      case AccountType.asset:
        return Colors.green;
      case AccountType.liability:
        return Colors.red;
      case AccountType.equity:
        return Colors.blue;
      case AccountType.income:
        return Colors.teal;
      case AccountType.expense:
        return Colors.orange;
    }
  }

  void _showAccountDetails(Account account) {
    // Show ledger in split-pane instead of navigating away
    setState(() {
      _selectedAccount = account;
    });
  }

  void _confirmDeleteAccount(Account account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Está seguro que desea eliminar la cuenta "${account.code} - ${account.name}"?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();

              try {
                final accountId = account.id;
                if (accountId == null || accountId.isEmpty) {
                  throw Exception('La cuenta no tiene identificador definido.');
                }

                await _accountingService.deleteAccount(accountId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cuenta eliminada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadAccounts();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al eliminar cuenta: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
