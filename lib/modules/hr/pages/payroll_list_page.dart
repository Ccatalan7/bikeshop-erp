import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/payroll_voucher_service.dart';
import '../models/payroll_voucher.dart';
import '../widgets/payroll_voucher_dialog.dart';
import '../widgets/payroll_payment_dialog.dart';
import '../widgets/employee_advance_dialog.dart';

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
  final Set<String> _settlementLoadingIds = {};
  final Set<String> _settlementLoadedIds = {};

  @override
  void initState() {
    super.initState();
    _loadVouchers();
  }

  Future<void> _loadVouchers({bool forceRefresh = false}) async {
    final service = context.read<PayrollVoucherService>();

    if (!forceRefresh && service.hasVouchersCache && _vouchers.isEmpty) {
      setState(() {
        _vouchers = List<PayrollVoucher>.from(service.cachedVouchers);
        _isLoading = false;
        _error = null;
      });
    } else {
      setState(() {
        _isLoading = _vouchers.isEmpty;
        _error = null;
      });
    }

    try {
      final vouchers = await service.fetchVouchers(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _vouchers = vouchers;
          _isLoading = false;
          if (forceRefresh) {
            _settlementLoadedIds.clear();
            _settlementLoadingIds.clear();
          }
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
      _loadVouchers(forceRefresh: true); // Refresh list
    }
  }

  Future<void> _openAdvanceDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const EmployeeAdvanceDialog(),
    );
    if (result == true && mounted) {
      _loadVouchers(forceRefresh: true);
    }
  }

  Future<void> _editVoucher(PayrollVoucher voucher) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PayrollVoucherDialog(existingVoucher: voucher),
    );
    if (result == true && mounted) {
      _loadVouchers(forceRefresh: true); // Refresh list
    }
  }

  /// Confirm a draft voucher (draft → confirmed)
  Future<void> _confirmVoucher(PayrollVoucher voucher) async {
    try {
      await context.read<PayrollVoucherService>().confirmVoucher(voucher.id!);
      if (mounted) _loadVouchers(forceRefresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Pay a confirmed voucher (confirmed → paid)
  Future<void> _payVoucher(PayrollVoucher voucher) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PayrollPaymentDialog(voucherId: voucher.id!),
    );

    if (result == true && mounted) {
      _loadVouchers(forceRefresh: true);
    }
  }

  /// Delete a draft voucher
  Future<void> _deleteVoucher(PayrollVoucher voucher) async {
    final service = context.read<PayrollVoucherService>();
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

    await service.deleteVoucher(voucher.id!);
    if (mounted) _loadVouchers(forceRefresh: true);
  }

  /// Revert confirmed voucher back to draft (confirmed → draft)
  Future<void> _revertToDraft(PayrollVoucher voucher) async {
    final service = context.read<PayrollVoucherService>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Volver a Borrador?'),
        content: const Text('La nómina volverá a estado editable.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Volver a Borrador'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await service.revertToDraft(voucher.id!);
      if (mounted) _loadVouchers(forceRefresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Cancel payment of a paid voucher (paid → confirmed)
  Future<void> _cancelPayment(PayrollVoucher voucher) async {
    final service = context.read<PayrollVoucherService>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar Pago?'),
        content: const Text(
            'Esto revertirá los pagos e imputaciones de anticipos. La obligación de sueldo seguirá confirmada.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, mantener')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sí, cancelar pago'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await service.revertPayment(voucher.id!);
      if (mounted) _loadVouchers(forceRefresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleVoucherExpansion(PayrollVoucher voucher) async {
    final voucherId = voucher.id;
    if (voucherId == null) return;

    final isExpanded = _expandedIds.contains(voucherId);
    setState(() {
      if (isExpanded) {
        _expandedIds.remove(voucherId);
      } else {
        _expandedIds.add(voucherId);
      }
    });

    if (isExpanded ||
        _settlementLoadedIds.contains(voucherId) ||
        _settlementLoadingIds.contains(voucherId)) {
      return;
    }

    setState(() => _settlementLoadingIds.add(voucherId));
    try {
      final hydrated = await context
          .read<PayrollVoucherService>()
          .hydrateVoucherSettlements(voucher);
      if (!mounted) return;

      setState(() {
        final index = _vouchers.indexWhere((item) => item.id == voucherId);
        if (index != -1) _vouchers[index] = hydrated;
        _settlementLoadedIds.add(voucherId);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando pagos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _settlementLoadingIds.remove(voucherId));
      }
    }
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
              TextButton(
                onPressed: _openAdvanceDialog,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Registrar anticipo'),
              ),
              const SizedBox(width: 4),
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
      onRefresh: () => _loadVouchers(forceRefresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vouchers.length,
        itemBuilder: (context, index) => _buildVoucherCard(_vouchers[index]),
      ),
    );
  }

  Widget _buildVoucherCard(PayrollVoucher voucher) {
    final isDraft = voucher.status == PayrollVoucherStatus.draft;
    final isConfirmed = voucher.status == PayrollVoucherStatus.confirmed;
    final isPartial = voucher.status == PayrollVoucherStatus.partial;
    final isPaid = voucher.status == PayrollVoucherStatus.paid;
    final isExpanded = _expandedIds.contains(voucher.id);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header row (always visible)
          InkWell(
            onTap: () => _toggleVoucherExpansion(voucher),
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
                          '${voucher.employeeCount} trabajadores • ${voucher.totalHours.toStringAsFixed(1)} hrs',
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
                  // === ACTIONS PER STATUS ===
                  // DRAFT: Edit, Confirm, Delete
                  if (isDraft) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      color: Colors.blue,
                      iconSize: 20,
                      tooltip: 'Editar',
                      onPressed: () => _editVoucher(voucher),
                    ),
                    FilledButton(
                      onPressed: () => _confirmVoucher(voucher),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Confirmar'),
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
                  // CONFIRMED/PARTIAL: register movements
                  if (isConfirmed || isPartial) ...[
                    FilledButton(
                      onPressed: () => _payVoucher(voucher),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(isPartial ? 'Registrar pago' : 'Pagar'),
                    ),
                    const SizedBox(width: 8),
                    if (isConfirmed)
                      OutlinedButton.icon(
                        onPressed: () => _revertToDraft(voucher),
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text('Borrador'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                        ),
                      ),
                    if (isPartial)
                      OutlinedButton.icon(
                        onPressed: () => _cancelPayment(voucher),
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text('Revertir movimientos'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                  ],
                  // PAID: Cancel Payment button
                  if (isPaid) ...[
                    const Chip(
                      label: Text('Pagado',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: Colors.green,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _cancelPayment(voucher),
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('Cancelar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded details
          if (isExpanded)
            _buildExpandedDetails(
              voucher,
              isLoadingSettlements: _settlementLoadingIds.contains(voucher.id),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandedDetails(
    PayrollVoucher voucher, {
    required bool isLoadingSettlements,
  }) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          const Divider(height: 1),
          if (isLoadingSettlements)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Cargando detalle de pagos...',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            )
          else ...[
            // Table header
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text('Trabajador',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(
                      child: Text('Horas',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.right)),
                  Expanded(
                      child: Text('Tarifa',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.right)),
                  Expanded(
                      child: Text('Total',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.right)),
                  Expanded(
                      child: Text('Pagado',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.right)),
                  Expanded(
                      child: Text('Pendiente',
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
                      Expanded(
                          child: Text(currency.format(line.settledAmount),
                              style: const TextStyle(fontSize: 13),
                              textAlign: TextAlign.right)),
                      Expanded(
                          child: Text(currency.format(line.balance),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: line.balance > 0
                                      ? Colors.orange[800]
                                      : Colors.green[700]),
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
        ],
      ),
    );
  }

  Color _getStatusColor(PayrollVoucherStatus status) {
    switch (status) {
      case PayrollVoucherStatus.paid:
        return Colors.green;
      case PayrollVoucherStatus.confirmed:
        return Colors.orange;
      case PayrollVoucherStatus.partial:
        return Colors.amber[800]!;
      case PayrollVoucherStatus.draft:
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(PayrollVoucherStatus status) {
    switch (status) {
      case PayrollVoucherStatus.paid:
        return Icons.check;
      case PayrollVoucherStatus.confirmed:
        return Icons.thumb_up;
      case PayrollVoucherStatus.partial:
        return Icons.payments_outlined;
      case PayrollVoucherStatus.draft:
        return Icons.edit_note;
      default:
        return Icons.help_outline;
    }
  }
}
