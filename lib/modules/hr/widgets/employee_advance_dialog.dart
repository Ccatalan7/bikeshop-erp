import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/hr_models.dart';
import '../services/hr_service.dart';
import '../services/payroll_voucher_service.dart';

class EmployeeAdvanceDialog extends StatefulWidget {
  const EmployeeAdvanceDialog({super.key});

  @override
  State<EmployeeAdvanceDialog> createState() => _EmployeeAdvanceDialogState();
}

class _EmployeeAdvanceDialogState extends State<EmployeeAdvanceDialog> {
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  List<Employee> _employees = const [];
  List<Map<String, dynamic>> _paymentMethods = const [];
  String? _employeeId;
  String? _paymentMethodId;
  DateTime _paidAt = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        context.read<HRService>().getEmployees(status: EmployeeStatus.active),
        context.read<PayrollVoucherService>().getPaymentMethods(),
      ]);
      if (!mounted) return;

      final employees = results[0] as List<Employee>;
      final methods = results[1] as List<Map<String, dynamic>>;
      setState(() {
        _employees = employees;
        _paymentMethods = methods;
        _employeeId = employees.isNotEmpty ? employees.first.id : null;
        _paymentMethodId =
            methods.isNotEmpty ? methods.first['id'] as String : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el formulario: $e')),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_paidAt),
    );
    if (!mounted) return;
    setState(() => _paidAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time?.hour ?? _paidAt.hour,
          time?.minute ?? _paidAt.minute,
        ));
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (_employeeId == null || _paymentMethodId == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona trabajador, método y monto.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await context.read<PayrollVoucherService>().registerEmployeeAdvance(
            employeeId: _employeeId!,
            amount: amount,
            paymentMethodId: _paymentMethodId!,
            paidAt: _paidAt,
            reference: _referenceController.text.trim().isEmpty
                ? null
                : _referenceController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anticipo registrado correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar el anticipo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd/MM/yyyy HH:mm', 'es_CL');

    return AlertDialog(
      title: const Text('Registrar anticipo'),
      content: SizedBox(
        width: 480,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Registra la salida de dinero ahora. Podrás imputarla a una nómina después.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _employeeId,
                    decoration: const InputDecoration(
                      labelText: 'Trabajador',
                      border: OutlineInputBorder(),
                    ),
                    items: _employees
                        .where((employee) => employee.id != null)
                        .map((employee) => DropdownMenuItem(
                              value: employee.id,
                              child: Text(employee.fullName),
                            ))
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _employeeId = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _amountController,
                          decoration: const InputDecoration(
                            labelText: 'Monto',
                            prefixText: '\$ ',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : _pickDate,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                          child: Text(formatter.format(_paidAt)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethodId,
                    decoration: const InputDecoration(
                      labelText: 'Método de pago',
                      border: OutlineInputBorder(),
                    ),
                    items: _paymentMethods
                        .map((method) => DropdownMenuItem(
                              value: method['id'] as String,
                              child: Text(method['name'] as String),
                            ))
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _paymentMethodId = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Referencia bancaria (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Guardando...' : 'Registrar anticipo'),
        ),
      ],
    );
  }
}
