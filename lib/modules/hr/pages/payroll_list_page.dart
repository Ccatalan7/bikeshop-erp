import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/payroll_voucher_service.dart';
import '../models/payroll_voucher.dart';
import '../widgets/payroll_voucher_dialog.dart';
import '../widgets/payroll_payment_dialog.dart';

class PayrollListPage extends StatefulWidget {
  const PayrollListPage({super.key});

  @override
  State<PayrollListPage> createState() => _PayrollListPageState();
}

class _PayrollListPageState extends State<PayrollListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PayrollVoucherService>().fetchVouchers();
    });
  }

  Future<void> _openVoucherDialog() async {
    await showDialog(
      context: context,
      builder: (context) => const PayrollVoucherDialog(),
    );
    if (mounted) {
      setState(() {}); // Trigger rebuild to refresh list
    }
  }

  Future<void> _payVoucher(PayrollVoucher voucher) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PayrollPaymentDialog(voucherId: voucher.id!),
    );

    if (result == true && mounted) {
      setState(() {}); // Refresh list
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Nóminas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nueva Nómina',
            onPressed: _openVoucherDialog,
          ),
        ],
      ),
      body: FutureBuilder<List<PayrollVoucher>>(
        future: context.read<PayrollVoucherService>().fetchVouchers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final vouchers = snapshot.data ?? [];
          if (vouchers.isEmpty) {
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

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: vouchers.length,
            itemBuilder: (context, index) {
              final voucher = vouchers[index];
              final isDraft = voucher.status == PayrollVoucherStatus.draft;
              final isPaid = voucher.status == PayrollVoucherStatus.paid;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Status Icon
                      CircleAvatar(
                        backgroundColor: _getStatusColor(voucher.status),
                        child: Icon(_getStatusIcon(voucher.status),
                            color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              voucher.periodLabel ??
                                  '${DateFormat('dd/MM').format(voucher.periodStart)} - ${DateFormat('dd/MM').format(voucher.periodEnd)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${voucher.employeeCount} empleados • ${voucher.totalHours} hrs',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            if (isPaid && voucher.paidAt != null)
                              Text(
                                'Pagado: ${DateFormat('dd/MM/yy HH:mm').format(voucher.paidAt!)}',
                                style: TextStyle(
                                    color: Colors.green[700], fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      // Amount
                      Text(
                        NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                            .format(voucher.totalAmount),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(width: 16),
                      // Actions
                      if (isDraft) ...[
                        FilledButton.icon(
                          onPressed: () => _payVoucher(voucher),
                          icon: const Icon(Icons.payments, size: 18),
                          label: const Text('Pagar'),
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.green),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          tooltip: 'Eliminar',
                          onPressed: () => _deleteVoucher(voucher),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
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
