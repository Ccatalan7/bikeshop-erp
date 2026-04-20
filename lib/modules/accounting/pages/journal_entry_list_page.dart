import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
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
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 800;

      return MainLayout(
        title: 'Asientos Contables',
        body: Column(
          children: [
            // Search and Filter Bar
            // Search and Filter Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: isMobile
                  ? Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SearchWidget(
                                hintText: 'Buscar...',
                                onSearchChanged: _onSearchChanged,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Compact Mobile Filter Button
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<JournalEntryType?>(
                                  value: _selectedType,
                                  hint: const Icon(Icons.filter_list, size: 20),
                                  icon: const SizedBox.shrink(),
                                  alignment: Alignment.center,
                                  items: [
                                    const DropdownMenuItem<JournalEntryType?>(
                                      value: null,
                                      child: Text('Todos'),
                                    ),
                                    ...JournalEntryType.values.map(
                                      (type) =>
                                          DropdownMenuItem<JournalEntryType?>(
                                        value: type,
                                        child: Text(type.displayName),
                                      ),
                                    ),
                                  ],
                                  onChanged: _onTypeFilterChanged,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              '${_filteredEntries.length} resultados',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed:
                                  _isLoading ? null : _loadJournalEntries,
                              icon: const Icon(Icons.refresh, size: 20),
                              constraints: const BoxConstraints(),
                              splashRadius: 20,
                              tooltip: 'Actualizar',
                            ),
                            const SizedBox(width: 12),
                            AppButton(
                              text: 'Nuevo',
                              onPressed: () => context
                                  .push('/accounting/journal-entries/new'),
                              icon: Icons.add,
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        SizedBox(
                          width: 320,
                          child: SearchWidget(
                            hintText: 'Buscar por número, descripción...',
                            onSearchChanged: _onSearchChanged,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          height: 24,
                          width: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                        const SizedBox(width: 16),
                        // Desktop Filter
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<JournalEntryType?>(
                              value: _selectedType,
                              hint: Text('Tipo de asiento',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600)),
                              icon: const Icon(Icons.arrow_drop_down,
                                  size: 20, color: Colors.grey),
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black87),
                              items: [
                                const DropdownMenuItem<JournalEntryType?>(
                                  value: null,
                                  child: Text('Todos los tipos'),
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
                        ),
                        const Spacer(),
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.only(right: 16),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        IconButton(
                          onPressed: _isLoading ? null : _loadJournalEntries,
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Actualizar',
                        ),
                        const SizedBox(width: 12),
                        AppButton(
                          text: 'Nuevo Asiento',
                          onPressed: () =>
                              context.push('/accounting/journal-entries/new'),
                          icon: Icons.add,
                        ),
                      ],
                    ),
            ),

            // Entries List
            Expanded(
              child: _isLoading
                  ? const Center(child: BrandedLoading())
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
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredEntries.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = _filteredEntries[index];
                            return _JournalEntryCard(
                              entry: entry,
                              dateFormat: _dateFormat,
                              currencyFormat: _currencyFormat,
                              onDelete: () => _quickDeleteEntry(entry),
                            );
                          },
                        ),
            ),
          ],
        ),
      );
    });
  }
}

class _JournalEntryCard extends StatelessWidget {
  final JournalEntry entry;
  final DateFormat dateFormat;
  final NumberFormat currencyFormat;
  final VoidCallback onDelete;

  const _JournalEntryCard({
    required this.entry,
    required this.dateFormat,
    required this.currencyFormat,
    required this.onDelete,
  });

  String _formatSource(String? module, String? ref) {
    if (module == null && ref == null) return '';
    String modName = module ?? '';
    if (module == 'sales_invoices') modName = 'Factura Venta';
    if (module == 'purchase_invoices') modName = 'Factura Compra';
    if (module == 'sales_payments') modName = 'Cobro Venta';
    if (module == 'purchase_payments') modName = 'Pago Compra';
    if (module == 'expenses') modName = 'Gasto';
    if (module == 'payroll') modName = 'Nómina';
    return '$modName ${ref ?? ''}'.trim();
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
      case JournalEntryType.payroll:
        return Colors.pink;
      case JournalEntryType.adjustment:
        return Colors.yellow.shade800;
      case JournalEntryType.closing:
        return Colors.red.shade800;
      case JournalEntryType.opening:
        return Colors.indigo;
    }
  }

  Color _getStatusColor(JournalEntryStatus status) {
    switch (status) {
      case JournalEntryStatus.draft:
        return Colors.amber.shade700;
      case JournalEntryStatus.posted:
        return Colors.green.shade700;
      case JournalEntryStatus.reversed:
        return Colors.red.shade700;
    }
  }

  IconData _getTypeIcon(JournalEntryType type) {
    switch (type) {
      case JournalEntryType.manual:
        return Icons.edit_note;
      case JournalEntryType.sales:
        return Icons.sell;
      case JournalEntryType.purchase:
        return Icons.shopping_cart;
      case JournalEntryType.payment:
        return Icons.payment;
      case JournalEntryType.receipt:
        return Icons.receipt;
      case JournalEntryType.payroll:
        return Icons.groups;
      default:
        return Icons.article;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceText = _formatSource(entry.sourceModule, entry.sourceReference);
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // Hide default trailing icon to manage layout manually
          trailing: const SizedBox.shrink(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT SIDE: Main Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Badge + Date
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            entry.entryNumber,
                            style: TextStyle(
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.calendar_today_outlined,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          dateFormat.format(entry.date),
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Description
                    Text(
                      entry.description.isEmpty
                          ? 'Sin descripción'
                          : entry.description,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFF1F2937),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),

                    // Meta Tags (Type, Status, Source)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Type
                        _buildBadge(
                          color: _getTypeColor(entry.type),
                          icon: _getTypeIcon(entry.type),
                          text: entry.type.displayName,
                        ),
                        // Status
                        _buildBadge(
                          color: _getStatusColor(entry.status),
                          text: entry.status.displayName,
                        ),
                        // Source
                        if (sourceText.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link,
                                  size: 14, color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 150),
                                child: Text(
                                  sourceText,
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        if (entry.hasStockAdjustmentOrigin)
                          _buildBadge(
                            color: Colors.blueGrey.shade600,
                            icon: Icons.inventory_2_outlined,
                            text: entry.stockAdjustmentOriginDisplay!,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // RIGHT SIDE: Actions & Amount
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Amount (Top Right)
                  Text(
                    currencyFormat.format(entry.totalDebit),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color:
                          entry.isBalanced ? Colors.grey.shade900 : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Actions (Bottom Right)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz,
                            size: 20, color: Colors.grey.shade400),
                        tooltip: 'Opciones',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (value) {
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Text('Eliminar',
                                    style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.keyboard_arrow_down,
                          size: 24, color: Colors.grey.shade400),
                    ],
                  ),
                ],
              ),
            ],
          ),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  // Table Header
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                            flex: 3,
                            child: Text('Cuenta',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700))),
                        if (isDesktop)
                          Expanded(
                              flex: 3,
                              child: Text('Descripción',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700))),
                        SizedBox(
                            width: 100,
                            child: Text('Debe',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700))),
                        SizedBox(
                            width: 100,
                            child: Text('Haber',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700))),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Lines
                  ...entry.lines.map((line) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${line.accountCode} ${line.accountName}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                                if (!isDesktop && line.description.isNotEmpty)
                                  Text(line.description,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                          if (isDesktop)
                            Expanded(
                              flex: 3,
                              child: Text(line.description,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600)),
                            ),
                          SizedBox(
                              width: 100,
                              child: Text(
                                  line.debitAmount > 0
                                      ? currencyFormat.format(line.debitAmount)
                                      : '-',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700))),
                          SizedBox(
                              width: 100,
                              child: Text(
                                  line.creditAmount > 0
                                      ? currencyFormat.format(line.creditAmount)
                                      : '-',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700))),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(
      {required Color color, IconData? icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
