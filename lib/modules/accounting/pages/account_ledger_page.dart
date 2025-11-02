import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/account.dart';

class AccountLedgerPage extends StatefulWidget {
  final Account account;

  const AccountLedgerPage({
    super.key,
    required this.account,
  });

  @override
  State<AccountLedgerPage> createState() => _AccountLedgerPageState();
}

class _AccountLedgerPageState extends State<AccountLedgerPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  DateTime? _startDate;
  DateTime? _endDate;
  double _balance = 0.0;
  double _debitTotal = 0.0;
  double _creditTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant ID found');
      }

      // Build query - use explicit relationship name to avoid ambiguity
      var query = _supabase
          .from('journal_lines')
          .select('''
            id,
            entry_id,
            account_id,
            description,
            debit_amount,
            credit_amount,
            created_at,
            tenant_id,
            journal_entries!journal_lines_entry_id_fkey(
              entry_number,
              entry_date,
              notes,
              source_reference,
              status
            )
          ''')
          .eq('account_id', widget.account.id!)
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false);

      final response = await query;

      final transactions = (response as List)
          .map((json) => json as Map<String, dynamic>)
          .toList();

      // Calculate totals
      double debitTotal = 0.0;
      double creditTotal = 0.0;
      for (final transaction in transactions) {
        debitTotal += (transaction['debit_amount'] as num?)?.toDouble() ?? 0.0;
        creditTotal += (transaction['credit_amount'] as num?)?.toDouble() ?? 0.0;
      }

      setState(() {
        _transactions = transactions;
        _debitTotal = debitTotal;
        _creditTotal = creditTotal;
        _balance = debitTotal - creditTotal;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando transacciones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadTransactions();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _loadTransactions();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return MainLayout(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.account.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Código: ${widget.account.code} • ${widget.account.category.displayName}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Date filter
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _selectDateRange,
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        _startDate != null && _endDate != null
                            ? '${DateFormat('dd/MM/yy').format(_startDate!)} - ${DateFormat('dd/MM/yy').format(_endDate!)}'
                            : 'Filtrar por fecha',
                      ),
                    ),
                    if (_startDate != null || _endDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearDateFilter,
                        tooltip: 'Limpiar filtro',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Summary cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    color: Colors.green[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Débitos',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currencyFormat.format(_debitTotal),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    color: Colors.red[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Créditos',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currencyFormat.format(_creditTotal),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saldo',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currencyFormat.format(_balance),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Transactions table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No hay transacciones',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Fecha')),
                              DataColumn(label: Text('Asiento')),
                              DataColumn(label: Text('Descripción')),
                              DataColumn(
                                label: Text('Débito'),
                                numeric: true,
                              ),
                              DataColumn(
                                label: Text('Crédito'),
                                numeric: true,
                              ),
                            ],
                            rows: _transactions.map((transaction) {
                              final entryData = transaction['journal_entries'] as Map<String, dynamic>?;
                              final entryNumber = entryData?['entry_number'] as String? ?? '';
                              final entryDate = entryData?['entry_date'] != null
                                  ? DateTime.parse(entryData!['entry_date'] as String)
                                  : null;
                              final description = entryData?['notes'] as String? ?? transaction['description'] as String? ?? '';
                              final debit = (transaction['debit_amount'] as num?)?.toDouble() ?? 0.0;
                              final credit = (transaction['credit_amount'] as num?)?.toDouble() ?? 0.0;

                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      entryDate != null
                                          ? DateFormat('dd/MM/yyyy').format(entryDate)
                                          : '-',
                                    ),
                                  ),
                                  DataCell(Text(entryNumber)),
                                  DataCell(
                                    SizedBox(
                                      width: 300,
                                      child: Text(
                                        description,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      debit > 0
                                          ? currencyFormat.format(debit)
                                          : '',
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      credit > 0
                                          ? currencyFormat.format(credit)
                                          : '',
                                      style: TextStyle(
                                        color: Colors.red[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
