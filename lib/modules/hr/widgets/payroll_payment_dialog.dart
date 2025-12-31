import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/payroll_voucher_service.dart';
import '../models/payroll_voucher.dart';

/// Dialog for confirming payment of a payroll voucher.
/// Allows selecting Payment Method (DB) and Source Account (DB) per employee.
class PayrollPaymentDialog extends StatefulWidget {
  final String voucherId;

  const PayrollPaymentDialog({super.key, required this.voucherId});

  @override
  State<PayrollPaymentDialog> createState() => _PayrollPaymentDialogState();
}

class _PayrollPaymentDialogState extends State<PayrollPaymentDialog> {
  PayrollVoucher? _voucher;
  bool _isLoading = true;
  bool _isProcessing = false;

  // Dynamic Data
  List<Map<String, dynamic>> _availableMethods = [];
  List<Map<String, dynamic>> _availableAccounts = [];

  // Selections [lineId] -> ID
  final Map<String, String> _selectedMethodIds = {};
  final Map<String, String> _selectedAccountIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final service = context.read<PayrollVoucherService>();

      // Load Voucher and Options in parallel
      final results = await Future.wait([
        service.getVoucher(widget.voucherId),
        service.getPaymentMethods(),
        service.getPaymentAccounts(),
      ]);

      if (mounted) {
        final voucher = results[0] as PayrollVoucher?;
        final methods = results[1] as List<Map<String, dynamic>>;
        final accounts = results[2] as List<Map<String, dynamic>>;

        if (voucher != null) {
          setState(() {
            _voucher = voucher;
            _availableMethods = methods;
            _availableAccounts = accounts;
            _isLoading = false;

            // Initialize selections from existing line data
            for (var line in voucher.lines) {
              if (line.id != null) {
                // Pre-select if saved, otherwise default
                if (line.paymentMethodId != null) {
                  _selectedMethodIds[line.id!] = line.paymentMethodId!;
                } else if (methods.isNotEmpty) {
                  // Default: Try to match legacy string or pick first
                  final match = methods.firstWhere(
                      (m) => m['name']
                          .toString()
                          .toLowerCase()
                          .contains(line.paymentMethod.toLowerCase()),
                      orElse: () => methods.first);
                  _selectedMethodIds[line.id!] = match['id'];
                }

                if (line.paymentAccountId != null) {
                  _selectedAccountIds[line.id!] = line.paymentAccountId!;
                } else {
                  // Auto-select account based on method
                  _autoSelectAccount(line.id!, _selectedMethodIds[line.id]);
                }
              }
            }
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error cargando datos: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _autoSelectAccount(String lineId, String? methodId) {
    if (methodId == null || _availableAccounts.isEmpty) return;

    final method = _availableMethods.firstWhere((m) => m['id'] == methodId,
        orElse: () => {});
    final methodName = (method['name'] ?? '').toString().toLowerCase();

    // Logic: If 'efectivo' -> find 'box' or 'cash' account
    // If 'transfer' -> find 'bank' account

    Map<String, dynamic>? match;

    if (methodName.contains('efectivo') ||
        methodName.contains('cash') ||
        methodName.contains('caja')) {
      // Find account with '1101' or name 'caja'
      match = _availableAccounts.firstWhere(
          (a) =>
              (a['code'] ?? '').toString().startsWith('1101') ||
              (a['name'] ?? '').toString().toLowerCase().contains('caja'),
          orElse: () => _availableAccounts.first);
    } else {
      // Assume Bank (1102)
      match = _availableAccounts.firstWhere(
          (a) =>
              (a['code'] ?? '').toString().startsWith('1102') ||
              (a['name'] ?? '').toString().toLowerCase().contains('banco'),
          orElse: () => _availableAccounts.first);
    }

    if (match != null) {
      _selectedAccountIds[lineId] = match['id'];
    }
  }

  Future<void> _confirmPayment() async {
    if (_voucher == null) return;

    setState(() => _isProcessing = true);

    try {
      final service = context.read<PayrollVoucherService>();

      // Update lines with explicit Primary Key selections
      for (var line in _voucher!.lines.where((l) => l.isIncluded)) {
        if (line.id == null) continue;

        final methodId = _selectedMethodIds[line.id];
        final accountId = _selectedAccountIds[line.id];

        // Update if changed or if missing
        if (methodId != line.paymentMethodId ||
            accountId != line.paymentAccountId) {
          await service.updateLine(line.copyWith(
            paymentMethodId: methodId,
            paymentAccountId: accountId,
            // Update legacy string just in case
            paymentMethod: _availableMethods.firstWhere(
                (m) => m['id'] == methodId,
                orElse: () => {'name': 'transfer'})['name'],
          ));
        }
      }

      // Process payment
      await service.payVoucher(_voucher!.id!);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ejecutado correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    if (_isLoading) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Cargando opciones de pago...')
            ],
          ),
        ),
      );
    }

    if (_voucher == null) return const SizedBox.shrink();

    final includedLines = _voucher!.lines.where((l) => l.isIncluded).toList();
    final totalAmount =
        includedLines.fold<double>(0, (sum, l) => sum + l.totalAmount);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Confirmar Pago de Nómina',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        Text(_voucher!.periodLabel ?? 'Sin período',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.9))),
                      ],
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),

            // Content
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: includedLines.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final line = includedLines[index];
                  // Ensure we have a valid selection or default
                  final currentMethodId = _selectedMethodIds[line.id];
                  final currentAccountId = _selectedAccountIds[line.id];

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Employee Info
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.employeeName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(
                                  '${line.workedHours} hrs + ${line.overtimeHours} extras',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(
                                'Cuenta Salario: ${line.salaryAccountId != null ? 'Configurada ✅' : '⚠️ Faltante'}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: line.salaryAccountId != null
                                        ? Colors.green
                                        : Colors.red),
                              ),
                            ],
                          ),
                        ),

                        // 2. Amount
                        Expanded(
                          flex: 2,
                          child: Center(
                            child: Text(
                              currency.format(line.totalAmount),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                        ),

                        // 3. Payment Selection (Method + Account)
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Method
                              DropdownButtonFormField<String>(
                                value: currentMethodId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Método de Pago',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 12),
                                ),
                                items: _availableMethods
                                    .map((m) => DropdownMenuItem(
                                        value: m['id'] as String,
                                        child: Text(m['name'])))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null && line.id != null) {
                                    setState(() {
                                      _selectedMethodIds[line.id!] = val;
                                      _autoSelectAccount(line.id!, val);
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 8),
                              // Account
                              DropdownButtonFormField<String>(
                                value: currentAccountId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Cuenta Origen (Banco/Caja)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 12),
                                ),
                                items: _availableAccounts
                                    .map((a) => DropdownMenuItem(
                                        value: a['id'] as String,
                                        child: Text(
                                            '${a['code']} - ${a['name']}')))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null && line.id != null)
                                    setState(() =>
                                        _selectedAccountIds[line.id!] = val);
                                },
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

            const Divider(height: 1),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.grey[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${includedLines.length} empleados'),
                      Text('Total: ${currency.format(totalAmount)}',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700])),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                          onPressed: _isProcessing
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancelar')),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: _isProcessing ? null : _confirmPayment,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check),
                        label: Text(
                            _isProcessing ? 'Procesando...' : 'Confirmar Pago'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 16)),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
