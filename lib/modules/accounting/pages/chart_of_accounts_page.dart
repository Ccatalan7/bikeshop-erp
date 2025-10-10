import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/database_service.dart';
import '../models/account.dart';
import '../services/accounting_service.dart';

class ChartOfAccountsPage extends StatefulWidget {
  const ChartOfAccountsPage({super.key});

  @override
  State<ChartOfAccountsPage> createState() => _ChartOfAccountsPageState();
}

class _ChartOfAccountsPageState extends State<ChartOfAccountsPage> {
  late AccountingService _accountingService;
  Map<AccountType, List<Account>> _chartOfAccounts = {};
  bool _isLoading = true;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _accountingService = AccountingService(
      Provider.of<DatabaseService>(context, listen: false),
    );
    _loadChartOfAccounts();
  }

  Future<void> _loadChartOfAccounts() async {
    setState(() => _isLoading = true);
    try {
      // Initialize Chilean chart of accounts if empty
      await _accountingService.initializeChileanChartOfAccounts();
      
      final chartOfAccounts = await _accountingService.getChartOfAccounts();
      setState(() {
        _chartOfAccounts = chartOfAccounts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando plan de cuentas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String searchTerm) {
    setState(() => _searchTerm = searchTerm);
  }

  Map<AccountType, List<Account>> _getFilteredAccounts() {
    if (_searchTerm.isEmpty) return _chartOfAccounts;
    
    final filtered = <AccountType, List<Account>>{};
    
    for (final entry in _chartOfAccounts.entries) {
      final filteredAccounts = entry.value
          .where((account) =>
              account.code.toLowerCase().contains(_searchTerm.toLowerCase()) ||
              account.name.toLowerCase().contains(_searchTerm.toLowerCase()))
          .toList();
      
      if (filteredAccounts.isNotEmpty) {
        filtered[entry.key] = filteredAccounts;
      }
    }
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Plan de Cuentas',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppButton(
                  text: 'Nueva Cuenta',
                  icon: Icons.add,
                  onPressed: () {
                    // TODO: Navigate to account form
                  },
                ),
              ],
            ),
          ),
          
          // Search
          SearchWidget(
            hintText: 'Buscar por código o nombre de cuenta...',
            onSearchChanged: _onSearchChanged,
          ),
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildChartOfAccounts(),
          ),
        ],
      ),
    );
  }

  Widget _buildChartOfAccounts() {
    final filteredAccounts = _getFilteredAccounts();
    
    if (filteredAccounts.isEmpty) {
      return const Center(
        child: Text(
          'No se encontraron cuentas',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        for (final entry in filteredAccounts.entries) ...[
          _buildAccountTypeSection(entry.key, entry.value),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildAccountTypeSection(AccountType type, List<Account> accounts) {
    final typeName = type.displayName;
    
    return Card(
      child: ExpansionTile(
        title: Text(
          typeName,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text('${accounts.length} cuenta${accounts.length != 1 ? 's' : ''}'),
        children: [
          ...accounts.map((account) => _buildAccountTile(account)),
        ],
      ),
    );
  }

  Widget _buildAccountTile(Account account) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _getAccountTypeColor(account.type).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            account.code.substring(0, 1),
            style: TextStyle(
              color: _getAccountTypeColor(account.type),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    title: Text(account.name),
    subtitle: Text('Código: ${account.code}\n${account.category.displayName}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!account.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Inactiva',
                style: TextStyle(
                  color: Colors.red[800],
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Navigate to edit account
            },
          ),
        ],
      ),
    );
  }

  Color _getAccountTypeColor(AccountType type) {
    switch (type) {
      case AccountType.asset:
        return Colors.green;
      case AccountType.liability:
        return Colors.red;
      case AccountType.equity:
        return Colors.blue;
      case AccountType.income:
        return Colors.purple;
      case AccountType.expense:
        return Colors.orange;
      case AccountType.tax:
        return Colors.teal;
    }
  }
}