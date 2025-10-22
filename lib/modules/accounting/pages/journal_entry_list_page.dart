import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/journal_entry.dart';
import '../services/accounting_service.dart';

class JournalEntryListPage extends StatefulWidget {
  const JournalEntryListPage({super.key});

  @override
  State<JournalEntryListPage> createState() => _JournalEntryListPageState();
}

class _JournalEntryListPageState extends State<JournalEntryListPage> {
  late AccountingService _accountingService;
  List<JournalEntry> _journalEntries = [];
  List<JournalEntry> _filteredEntries = [];
  bool _isLoading = true;
  String _searchTerm = '';
  JournalEntryType? _selectedType;
  final DateFormat _dateFormat = ChileanUtils.dateFormat;
  final NumberFormat _currencyFormat = ChileanUtils.currencyFormat;

  @override
  void initState() {
    super.initState();
    _accountingService = Provider.of<AccountingService>(context, listen: false);
    // Delay the load to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadJournalEntries();
    });
  }

  Future<void> _loadJournalEntries() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Force reload from database to get fresh data
      await _accountingService.reloadJournalEntries();
      final entries = await _accountingService.getJournalEntries();

      if (!mounted) return;
      setState(() {
        _journalEntries = entries;
        _filteredEntries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando asientos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterEntries() {
    if (!mounted) return;
    setState(() {
      _filteredEntries = _journalEntries.where((entry) {
        final matchesSearch = _searchTerm.isEmpty ||
            entry.entryNumber
                .toLowerCase()
                .contains(_searchTerm.toLowerCase()) ||
            entry.description
                .toLowerCase()
                .contains(_searchTerm.toLowerCase()) ||
            (entry.sourceModule
                    ?.toLowerCase()
                    .contains(_searchTerm.toLowerCase()) ??
                false) ||
            (entry.sourceReference
                    ?.toLowerCase()
                    .contains(_searchTerm.toLowerCase()) ??
                false);

        final matchesType =
            _selectedType == null || entry.type == _selectedType;

        return matchesSearch && matchesType;
      }).toList();
    });
  }

  void _onSearchChanged(String value) {
    if (!mounted) return;
    setState(() => _searchTerm = value);
    _filterEntries();
  }

  void _onTypeFilterChanged(JournalEntryType? type) {
    if (!mounted) return;
    setState(() => _selectedType = type);
    _filterEntries();
  }

  // 🗑️ TEMP: Quick delete for testing (no confirmation)
  Future<void> _quickDeleteEntry(JournalEntry entry) async {
    // Check if entry has ID
    if (entry.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Entrada sin ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Delete journal entry using accounting service
      await _accountingService.deleteJournalEntry(entry.id!);

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Asiento ${entry.entryNumber} eliminado'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );

      // Reload entries
      await _loadJournalEntries();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Asientos Contables',
      body: Column(
        children: [
          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SearchWidget(
                        hintText: 'Buscar por número, descripción, módulo...',
                        onSearchChanged: _onSearchChanged,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<JournalEntryType?>(
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
                          const DropdownMenuItem<JournalEntryType?>(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...JournalEntryType.values.map(
                            (type) => DropdownMenuItem<JournalEntryType?>(
                              value: type,
                              child: Text(type.displayName),
                            ),
                          ),
                        ],
                        onChanged: _onTypeFilterChanged,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: _isLoading ? null : _loadJournalEntries,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Actualizar',
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      text: 'Nuevo Asiento',
                      onPressed: () =>
                          context.push('/accounting/journal-entries/new'),
                      icon: Icons.add,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Total: ${_filteredEntries.length} asientos',
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
          ),

          // Entries List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredEntries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long,
                              size: 64,
                              color: Theme.of(context).disabledColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchTerm.isEmpty && _selectedType == null
                                  ? 'No hay asientos contables registrados'
                                  : 'No se encontraron asientos que coincidan con los filtros',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Theme.of(context).disabledColor,
                                  ),
                            ),
                            if (_searchTerm.isEmpty &&
                                _selectedType == null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Los asientos se crean automáticamente con las ventas y compras',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context).disabledColor,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _filteredEntries[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ExpansionTile(
                              title: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.entryNumber,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        Text(
                                          _dateFormat.format(entry.date),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      entry.description,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getTypeColor(entry.type)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _getTypeColor(entry.type),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        entry.type.displayName,
                                        style: TextStyle(
                                          color: _getTypeColor(entry.type),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(entry.status)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _getStatusColor(entry.status),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      entry.status.displayName,
                                      style: TextStyle(
                                        color: _getStatusColor(entry.status),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _currencyFormat.format(entry.totalDebit),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: entry.isBalanced
                                              ? null
                                              : Colors.red,
                                        ),
                                  ),
                                ],
                              ),
                              subtitle: entry.sourceModule != null ||
                                      entry.sourceReference != null
                                  ? Text(
                                      '${entry.sourceModule ?? ''} ${entry.sourceReference ?? ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                          ),
                                    )
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 🗑️ TEMP: Quick delete button for testing
                                  IconButton(
                                    onPressed: () => _quickDeleteEntry(entry),
                                    icon: const Icon(Icons.delete_forever,
                                        color: Colors.red, size: 20),
                                    tooltip: 'Eliminar (Testing)',
                                  ),
                                ],
                              ),
                              children: [
                                Container(
                                  margin:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Divider(),
                                      Text(
                                        'Líneas del Asiento',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 12),
                                      // Column headers for journal lines
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceVariant,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          children: [
                                            const Expanded(
                                              flex: 3,
                                              child: Text(
                                                'Cuenta',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const Expanded(
                                              flex: 3,
                                              child: Text(
                                                'Descripción',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                'Debe',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                'Haber',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...entry.lines
                                          .map((line) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(
                                                      color: Theme.of(context)
                                                          .dividerColor,
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 3,
                                                      child: Text(
                                                        '${line.accountCode} - ${line.accountName}',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 3,
                                                      child: Text(
                                                        line.description,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall,
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 120,
                                                      child: Text(
                                                        line.debitAmount > 0
                                                            ? _currencyFormat
                                                                .format(line
                                                                    .debitAmount)
                                                            : '',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                        textAlign:
                                                            TextAlign.right,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    SizedBox(
                                                      width: 120,
                                                      child: Text(
                                                        line.creditAmount > 0
                                                            ? _currencyFormat
                                                                .format(line
                                                                    .creditAmount)
                                                            : '',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                        textAlign:
                                                            TextAlign.right,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ))
                                          .toList(),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: entry.isBalanced
                                              ? Colors.green.withOpacity(0.1)
                                              : Colors.red.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: entry.isBalanced
                                                ? Colors.green
                                                : Colors.red,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              entry.isBalanced
                                                  ? Icons.check_circle
                                                  : Icons.error,
                                              color: entry.isBalanced
                                                  ? Colors.green
                                                  : Colors.red,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              entry.isBalanced
                                                  ? 'Asiento balanceado'
                                                  : 'Asiento desbalanceado',
                                              style: TextStyle(
                                                color: entry.isBalanced
                                                    ? Colors.green
                                                    : Colors.red,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              'Debe: ${_currencyFormat.format(entry.totalDebit)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            const SizedBox(width: 16),
                                            Text(
                                              'Haber: ${_currencyFormat.format(entry.totalCredit)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(JournalEntryType type) {
    switch (type) {
      case JournalEntryType.manual:
        return Colors.blue;
      case JournalEntryType.sales:
        return Colors.green;
      case JournalEntryType.purchase:
        return Colors.orange;
      case JournalEntryType.payment:
        return Colors.purple;
      case JournalEntryType.receipt:
        return Colors.teal;
      case JournalEntryType.adjustment:
        return Colors.yellow.shade700;
      case JournalEntryType.closing:
        return Colors.red;
      case JournalEntryType.opening:
        return Colors.indigo;
    }
  }

  Color _getStatusColor(JournalEntryStatus status) {
    switch (status) {
      case JournalEntryStatus.draft:
        return Colors.grey;
      case JournalEntryStatus.posted:
        return Colors.green;
      case JournalEntryStatus.reversed:
        return Colors.red;
    }
  }
}
