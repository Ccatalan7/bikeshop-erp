import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/themes/app_theme.dart';
import '../models/account.dart';
import '../services/accounting_service.dart';

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
    final isMobile = AppTheme.isMobile(context);
    final theme = Theme.of(context);
    
    return MainLayout(
      title: 'Plan de Cuentas',
      body: Column(
        children: [
          // Search and Filter Bar
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Column(
              children: [
                if (isMobile) ...[
                  // Mobile: Vertical layout
                  SearchWidget(
                    hintText: 'Buscar por código o nombre...',
                    onSearchChanged: _onSearchChanged,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<AccountType?>(
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          value: _selectedType,
                          items: [
                            const DropdownMenuItem<AccountType?>(
                              value: null,
                              child: Text(
                                'Todos',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ...AccountType.values.map(
                              (type) => DropdownMenuItem<AccountType?>(
                                value: type,
                                child: Text(
                                  type.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: _onTypeFilterChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        onPressed: () => context.push('/accounting/accounts/new'),
                        icon: const Icon(Icons.add),
                        iconSize: 24,
                        tooltip: 'Nueva Cuenta',
                      ),
                    ],
                  ),
                ] else ...[
                  // Desktop: Horizontal layout
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
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Total: ${_filteredAccounts.length} cuentas',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
          ),

          // Accounts List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredAccounts.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.account_balance,
                                size: 64,
                                color: theme.disabledColor,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchTerm.isEmpty && _selectedType == null
                                    ? 'No hay cuentas registradas'
                                    : 'No se encontraron cuentas que coincidan con los filtros',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.disabledColor,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(isMobile ? 8 : 16),
                        itemCount: _filteredAccounts.length,
                        itemBuilder: (context, index) {
                          final account = _filteredAccounts[index];
                          return Card(
                            margin: EdgeInsets.only(bottom: isMobile ? 6 : 8),
                            child: ListTile(
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _getTypeColor(account.type)
                                      .withOpacity(0.1),
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getTypeColor(account.type)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (account.description != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      account.description!,
                                      style: theme.textTheme.bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      context.push(
                                          '/accounting/accounts/${account.id}/edit');
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
                                      leading:
                                          Icon(Icons.delete, color: Colors.red),
                                      title: Text('Eliminar',
                                          style: TextStyle(color: Colors.red)),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _showAccountDetails(account),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
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
      case AccountType.tax:
        return Colors.purple;
    }
  }

  void _showAccountDetails(Account account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${account.code} - ${account.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Código', account.code),
            _buildDetailRow('Nombre', account.name),
            _buildDetailRow('Tipo', account.type.displayName),
            _buildDetailRow('Categoría', account.category.displayName),
            if (account.description != null)
              _buildDetailRow('Descripción', account.description!),
            _buildDetailRow('Estado', account.isActive ? 'Activa' : 'Inactiva'),
            if (account.createdAt != null)
              _buildDetailRow(
                  'Creada', account.createdAt.toString().split(' ')[0]),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/accounting/accounts/${account.id}/edit');
            },
            child: const Text('Editar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
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
