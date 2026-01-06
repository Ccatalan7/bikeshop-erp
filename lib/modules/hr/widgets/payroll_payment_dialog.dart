import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
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

  // Split payments (UI only): [lineId] -> list of splits
  final Map<String, List<_PaymentSplitDraft>> _paymentSplitsByLineId = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double _sumSplits(String lineId) {
    final splits = _paymentSplitsByLineId[lineId] ?? const <_PaymentSplitDraft>[];
    return splits.fold<double>(0, (sum, s) => sum + s.amount);
  }

  void _addSplit(String lineId, double totalAmount) {
    final current = _paymentSplitsByLineId[lineId] ?? <_PaymentSplitDraft>[];
    final used = current.fold<double>(0, (sum, s) => sum + s.amount);
    final remaining = (totalAmount - used).clamp(0, totalAmount);

    setState(() {
      _paymentSplitsByLineId[lineId] = [
        ...current,
        _PaymentSplitDraft(
          methodId: null,
          amount: remaining > 0 ? remaining.toDouble() : 0.0,
        ),
      ];
    });
  }

  void _removeSplit(String lineId, int index) {
    final current = _paymentSplitsByLineId[lineId];
    if (current == null || current.length <= 1) return;
    if (index < 0 || index >= current.length) return;

    setState(() {
      current[index].dispose();
      current.removeAt(index);
    });
  }

  bool _validateSplits(List<PayrollVoucherLine> includedLines) {
    for (final line in includedLines) {
      final lineId = line.id;
      if (lineId == null) continue;

      final splits = _paymentSplitsByLineId[lineId] ?? const <_PaymentSplitDraft>[];
      if (splits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falta método de pago para ${line.employeeName}.'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      for (final split in splits) {
        if (split.amount <= 0) continue;
        if (split.methodId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selecciona método de pago para ${line.employeeName}.'),
              backgroundColor: Colors.red,
            ),
          );
          return false;
        }
      }

      final sum = _sumSplits(lineId);
      if ((sum - line.totalAmount).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Los montos de pago de ${line.employeeName} deben sumar ${line.totalAmount.toStringAsFixed(0)}.'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic>? _buildSplitsPayload(List<PayrollVoucherLine> includedLines) {
    final payload = <String, dynamic>{};

    for (final line in includedLines) {
      final lineId = line.id;
      if (lineId == null) continue;
      final splits = _paymentSplitsByLineId[lineId];
      if (splits == null || splits.isEmpty) continue;

      payload[lineId] = splits
          .where((s) => s.amount > 0)
          .map((s) => {
                'payment_method_id': s.methodId,
                'amount': s.amount,
              })
          .toList();
    }

    return payload.isEmpty ? null : payload;
  }

  @override
  void dispose() {
    for (final splits in _paymentSplitsByLineId.values) {
      for (final s in splits) {
        s.dispose();
      }
    }
    super.dispose();
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
              {
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

            // Ensure split payments exist for every line (UI always shows at least 1 row)
            for (final line in voucher.lines) {
              final lineId = line.id;
              if (lineId == null) continue;
              if (_paymentSplitsByLineId.containsKey(lineId)) continue;

              final methodId = _selectedMethodIds[lineId] ??
                  (methods.isNotEmpty ? methods.first['id'] as String : null);

              _paymentSplitsByLineId[lineId] = [
                _PaymentSplitDraft(
                  methodId: methodId,
                  amount: line.totalAmount,
                ),
              ];
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

      final includedLines = _voucher!.lines.where((l) => l.isIncluded).toList();
      if (!_validateSplits(includedLines)) {
        setState(() => _isProcessing = false);
        return;
      }

      // Update lines with payment method selections
      for (var line in includedLines) {
        if (line.id == null) continue;

        // Update line logic
        final em = _employeeMap[line.employeeId];

        final splits = _paymentSplitsByLineId[line.id!] ?? const <_PaymentSplitDraft>[];
        final primaryMethodId = splits.isNotEmpty
          ? (splits
              .firstWhere((s) => s.amount > 0, orElse: () => splits.first)
              .methodId ??
            _selectedMethodIds[line.id] ??
            line.paymentMethodId)
          : (_selectedMethodIds[line.id] ?? line.paymentMethodId);

        // Sync salary account from current profile if available
        final salaryAccountId = em?.salaryAccountId ?? line.salaryAccountId;

        // Determine method name for legacy string
        String? methodName = line.paymentMethod;
        if (primaryMethodId != null) {
          final m = _availableMethods.firstWhere((m) => m['id'] == primaryMethodId,
              orElse: () => {'name': 'transfer'});
          methodName = m['name'];
        }

        // Only update if something changed (Method or Account mismatch)
        if (primaryMethodId != line.paymentMethodId ||
            salaryAccountId != line.salaryAccountId) {
          await service.updateLine(line.copyWith(
            paymentMethodId: primaryMethodId,
            paymentMethod: methodName,
            salaryAccountId: salaryAccountId,
          ));
        }
      }

      // Process payment
      await service.payVoucher(
        _voucher!.id!,
        paymentSplits: _buildSplitsPayload(includedLines),
      );

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
                  final lineId = line.id;
                  final splits = lineId == null
                      ? const <_PaymentSplitDraft>[]
                      : (_paymentSplitsByLineId[lineId] ?? const <_PaymentSplitDraft>[]);
                  final splitSum = lineId == null ? 0.0 : _sumSplits(lineId);
                  final delta = line.totalAmount - splitSum;

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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ...List.generate(splits.length, (i) {
                                final split = splits[i];

                                return Padding(
                                  padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: split.methodId,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            labelText:
                                                i == 0 ? 'Métodos de Pago' : null,
                                            isDense: true,
                                            border: const OutlineInputBorder(),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10, vertical: 12),
                                          ),
                                          items: _availableMethods
                                              .map((m) => DropdownMenuItem(
                                                  value: m['id'] as String,
                                                  child: Text(m['name'])))
                                              .toList(),
                                          onChanged: _isProcessing
                                              ? null
                                              : (val) {
                                                  if (lineId == null) return;
                                                  setState(() {
                                                    split.methodId = val;
                                                  });
                                                },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 150,
                                        child: TextFormField(
                                          controller: split.amountController,
                                          decoration: InputDecoration(
                                            labelText: i == 0 ? 'Monto' : null,
                                            isDense: true,
                                            border: const OutlineInputBorder(),
                                            prefixText: '\$ ',
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10, vertical: 12),
                                          ),
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.digitsOnly,
                                          ],
                                          onChanged: _isProcessing
                                              ? null
                                              : (_) => setState(() {}),
                                        ),
                                      ),
                                      if (lineId != null && splits.length > 1)
                                        IconButton(
                                          tooltip: 'Quitar método',
                                          onPressed: _isProcessing
                                              ? null
                                              : () => _removeSplit(lineId, i),
                                          icon: const Icon(Icons.close),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                              if (lineId != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        delta.abs() <= 0.01
                                            ? 'OK: suma exacta'
                                            : (delta > 0
                                                ? 'Faltan ${currency.format(delta)}'
                                                : 'Exceso ${currency.format(-delta)}'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: delta.abs() <= 0.01
                                              ? Colors.green
                                              : Colors.red,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: _isProcessing
                                            ? null
                                            : () => _addSplit(
                                                lineId, line.totalAmount),
                                        icon:
                                            const Icon(Icons.add, size: 18),
                                        label: const Text('Agregar método'),
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

class _PaymentSplitDraft {
  String? methodId;
  final TextEditingController amountController;

  _PaymentSplitDraft({
    required double amount,
    this.methodId,
  }) : amountController =
            TextEditingController(text: amount.toStringAsFixed(0));

  double get amount => double.tryParse(amountController.text) ?? 0;

  void dispose() {
    amountController.dispose();
  }
}
