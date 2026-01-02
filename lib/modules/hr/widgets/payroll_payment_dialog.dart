import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/payroll_voucher_service.dart';
import '../services/hr_service.dart';
import '../models/payroll_voucher.dart';
import '../models/hr_models.dart';

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
  Map<String, Employee> _employeeMap = {}; // Cache for profiles

  // Selections [lineId] -> methodId
  final Map<String, String> _selectedMethodIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final service = context.read<PayrollVoucherService>();
      final hrService = context.read<HRService>();

      // Load Voucher, Methods, and Current Employee Profiles in parallel
      final results = await Future.wait([
        service.getVoucher(widget.voucherId),
        service.getPaymentMethods(),
        hrService
            .getEmployees(), // Fetch current profiles to respect latest preferences
      ]);

      if (mounted) {
        final voucher = results[0] as PayrollVoucher?;
        final methods = results[1] as List<Map<String, dynamic>>;
        final employees = results[2] as List<Employee>;

        // Cache employees for salary account lookup
        _employeeMap = {
          for (var e in employees)
            if (e.id != null) e.id!: e
        };

        // Create a map of updated employee preferences: ID -> preferredPaymentMethodId
        final empPreferences = <String, String>{};
        for (var e in employees) {
          if (e.id != null && e.preferredPaymentMethodId != null) {
            empPreferences[e.id!] = e.preferredPaymentMethodId!;
          }
        }

        if (voucher != null) {
          setState(() {
            _voucher = voucher;
            _availableMethods = methods;
            _isLoading = false;

            // Initialize selections
            for (var line in voucher.lines) {
              if (line.id != null && line.employeeId != null) {
                String? targetMethodId;

                // 1. Try to use Current Employee Profile Preference (Highest Priority)
                if (empPreferences.containsKey(line.employeeId)) {
                  targetMethodId = empPreferences[line.employeeId];
                }

                // 2. Fallback to what was saved on the line
                targetMethodId ??= line.paymentMethodId;

                if (targetMethodId != null) {
                  // Verify the ID still exists in available methods
                  if (methods.any((m) => m['id'] == targetMethodId)) {
                    _selectedMethodIds[line.id!] = targetMethodId;
                    continue;
                  }
                }

                // 3. Fallback to legacy string matching if still no valid ID
                if (methods.isNotEmpty) {
                  final lineMethod = line.paymentMethod.toLowerCase();
                  final match = methods.firstWhere((m) {
                    final dbName = m['name'].toString().toLowerCase();
                    if (dbName.contains(lineMethod)) return true;
                    if (lineMethod == 'cash' && dbName.contains('efectivo'))
                      return true;
                    if (lineMethod == 'check' && dbName.contains('cheque'))
                      return true;
                    return false;
                  }, orElse: () => methods.first);

                  _selectedMethodIds[line.id!] = match['id'];
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

  Future<void> _confirmPayment() async {
    if (_voucher == null) return;

    setState(() => _isProcessing = true);

    try {
      final service = context.read<PayrollVoucherService>();

      // Update lines with payment method selections
      for (var line in _voucher!.lines.where((l) => l.isIncluded)) {
        if (line.id == null) continue;

        // Update line logic
        final em = _employeeMap[line.employeeId];

        // Use updated method, or keep existing
        final methodId = _selectedMethodIds[line.id] ?? line.paymentMethodId;

        // Sync salary account from current profile if available
        final salaryAccountId = em?.salaryAccountId ?? line.salaryAccountId;

        // Determine method name for legacy string
        String? methodName = line.paymentMethod;
        if (methodId != null) {
          final m = _availableMethods.firstWhere((m) => m['id'] == methodId,
              orElse: () => {'name': 'transfer'});
          methodName = m['name'];
        }

        // Only update if something changed (Method or Account mismatch)
        if (methodId != line.paymentMethodId ||
            salaryAccountId != line.salaryAccountId) {
          await service.updateLine(line.copyWith(
            paymentMethodId: methodId,
            paymentMethod: methodName,
            salaryAccountId: salaryAccountId,
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
                  final currentMethodId = _selectedMethodIds[line.id];

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
                                  '${line.workedHours.toStringAsFixed(1)} hrs${line.overtimeHours > 0 ? ' + ${line.overtimeHours.toStringAsFixed(1)} extras' : ''}',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 13)),
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

                        // 3. Payment Method Only (accounting handled automatically)
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<String>(
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
                                });
                              }
                            },
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
