import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/payroll_voucher_service.dart';
import '../models/payroll_voucher.dart';
import '../widgets/payroll_voucher_dialog.dart';
import '../widgets/payroll_payment_dialog.dart';

/// Payroll Voucher List - designed to be embedded in MainLayout
/// Uses ExpansionTile for inline details, no separate Scaffold/AppBar
class PayrollListPage extends StatefulWidget {
  const PayrollListPage({super.key});

  @override
  State<PayrollListPage> createState() => _PayrollListPageState();
}

class _PayrollListPageState extends State<PayrollListPage> {
  List<PayrollVoucher> _vouchers = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _loadVouchers();
  }

  Future<void> _loadVouchers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final vouchers =
          await context.read<PayrollVoucherService>().fetchVouchers();
      if (mounted) {
        setState(() {
          _vouchers = vouchers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openVoucherDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const PayrollVoucherDialog(),
    );
    if (result == true && mounted) {
      _loadVouchers(); // Refresh list
    }
  }

  Future<void> _editVoucher(PayrollVoucher voucher) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PayrollVoucherDialog(existingVoucher: voucher),
    );
    if (result == true && mounted) {
      _loadVouchers(); // Refresh list
    }
  }

  Future<void> _payVoucher(PayrollVoucher voucher) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PayrollPaymentDialog(voucherId: voucher.id!),
    );

    if (result == true && mounted) {
      _loadVouchers(); // Refresh list
    }
  }

  Future<void> _deleteVoucher(PayrollVoucher voucher) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Borrador?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await context.read<PayrollVoucherService>().deleteVoucher(voucher.id!);
    if (mounted) _loadVouchers();
  }

  Future<void> _revertToDraft(PayrollVoucher voucher) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Revertir a Borrador?'),
        content: const Text(
            'Esto eliminará los gastos y asientos contables asociados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Revertir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await context.read<PayrollVoucherService>().revertToDraft(voucher.id!);
    if (mounted) _loadVouchers();
  }

  @override
  Widget build(BuildContext context) {
    // NO Scaffold - this is embedded in MainLayout
    return Column(
      children: [
        // Header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Historial de Nóminas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                tooltip: 'Nueva Nómina',
                onPressed: _openVoucherDialog,
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_vouchers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No hay nóminas registradas'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openVoucherDialog,
              icon: const Icon(Icons.add),
              label: const Text('Crear Primera Nómina'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadVouchers,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vouchers.length,
        itemBuilder: (context, index) => _buildVoucherCard(_vouchers[index]),
      ),
    );
  }

  Widget _buildVoucherCard(PayrollVoucher voucher) {
    final isDraft = voucher.status == PayrollVoucherStatus.draft;
    final isPaid = voucher.status == PayrollVoucherStatus.paid;
    final isPending = voucher.status == PayrollVoucherStatus.pending;
    final isExpanded = _expandedIds.contains(voucher.id);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header row (always visible)
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedIds.remove(voucher.id);
                } else {
                  _expandedIds.add(voucher.id!);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Expand/collapse icon
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  // Status icon
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _getStatusColor(voucher.status),
                    child: Icon(_getStatusIcon(voucher.status),
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          voucher.periodLabel ??
                              '${DateFormat('dd/MM').format(voucher.periodStart)} - ${DateFormat('dd/MM').format(voucher.periodEnd)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          '${voucher.employeeCount} empleados • ${voucher.totalHours.toStringAsFixed(1)} hrs',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Amount
                  Text(
                    currency.format(voucher.totalAmount),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(width: 12),
                  // Actions
                  if (isDraft) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      color: Colors.blue,
                      iconSize: 20,
                      tooltip: 'Editar',
                      onPressed: () => _editVoucher(voucher),
                    ),
                    FilledButton(
                      onPressed: () => _payVoucher(voucher),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Pagar'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.red,
                      iconSize: 20,
                      tooltip: 'Eliminar',
                      onPressed: () => _deleteVoucher(voucher),
                    ),
                  ],
                  if (isPending) ...[
                    OutlinedButton.icon(
                      onPressed: () => _revertToDraft(voucher),
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('Revertir'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                      ),
                    ),
                  ],
                  if (isPaid)
                    Chip(
                      label: const Text('Pagado',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: Colors.green,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
          ),
          // Expanded details
          if (isExpanded) _buildExpandedDetails(voucher),
        ],
      ),
    );
  }

  Widget _buildExpandedDetails(PayrollVoucher voucher) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          const Divider(height: 1),
          // Table header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                    flex: 3,
                    child: Text('Empleado',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12))),
                const Expanded(
                    child: Text('Horas',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right)),
                const Expanded(
                    child: Text('Tarifa',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right)),
                const Expanded(
                    child: Text('Total',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Lines
          ...voucher.lines.where((l) => l.isIncluded).map((line) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: Text(line.employeeName,
                            style: const TextStyle(fontSize: 13))),
                    Expanded(
                        child: Text(line.workedHours.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 13),
                            textAlign: TextAlign.right)),
                    Expanded(
                        child: Text(currency.format(line.hourlyRate),
                            style: const TextStyle(fontSize: 13),
                            textAlign: TextAlign.right)),
                    Expanded(
                        child: Text(currency.format(line.totalAmount),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.right)),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          // Footer with totals
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Total: ',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                Text(currency.format(voucher.totalAmount),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(PayrollVoucherStatus status) {
    switch (status) {
      case PayrollVoucherStatus.paid:
        return Colors.green;
      case PayrollVoucherStatus.pending:
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _getStatusIcon(PayrollVoucherStatus status) {
    switch (status) {
      case PayrollVoucherStatus.paid:
        return Icons.check;
      case PayrollVoucherStatus.pending:
        return Icons.access_time;
      default:
        return Icons.edit_note;
    }
  }
}
