import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../models/purchase_invoice.dart';

/// Payment Form Page for Purchase Invoices
/// Handles payment registration for both Standard and Prepayment models
class PurchasePaymentFormPage extends StatefulWidget {
  final String invoiceId;
  final PurchaseInvoice invoice;

  const PurchasePaymentFormPage({
    super.key,
    required this.invoiceId,
    required this.invoice,
  });

  @override
  State<PurchasePaymentFormPage> createState() => _PurchasePaymentFormPageState();
}

class _PurchasePaymentFormPageState extends State<PurchasePaymentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  String _paymentMethod = 'transfer';
  String? _selectedBankAccount;
  DateTime _paymentDate = DateTime.now();
  bool _isSaving = false;

  List<Map<String, dynamic>> _bankAccounts = [];
  bool _isLoadingAccounts = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill amount with invoice balance
    _amountController.text = widget.invoice.balance.toStringAsFixed(0);
    _loadBankAccounts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadBankAccounts() async {
    try {
      // Load bank accounts (asset accounts that are cash/bank)
      // Adjust this query based on your actual account structure
      final response = await Supabase.instance.client
          .from('accounts')
          .select()
          .eq('account_type', 'asset')
          .or('code.like.11%,code.like.10%') // Cash and bank accounts typically start with 11 or 10
          .eq('is_active', true)
          .order('code');

      if (mounted) {
        setState(() {
          _bankAccounts = List<Map<String, dynamic>>.from(response);
          if (_bankAccounts.isNotEmpty) {
            _selectedBankAccount = _bankAccounts.first['id'].toString();
          }
          _isLoadingAccounts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAccounts = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading bank accounts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _savePayment() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedBankAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar una cuenta bancaria'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll('.', '').replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingrese un monto válido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (amount > widget.invoice.balance) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Monto mayor al saldo'),
          content: Text(
            'El monto ingresado (${ChileanUtils.formatCurrency(amount)}) '
            'es mayor al saldo de la factura (${ChileanUtils.formatCurrency(widget.invoice.balance)}).\n\n'
            '¿Desea continuar de todas formas?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    setState(() => _isSaving = true);

    try {
      // Create payment record
      final paymentData = {
        'purchase_invoice_id': widget.invoiceId,
        'payment_date': _paymentDate.toIso8601String(),
        'amount': amount,
        'payment_method': _paymentMethod,
        'bank_account_id': _selectedBankAccount,
        'reference': _referenceController.text.trim().isEmpty 
            ? null 
            : _referenceController.text.trim(),
        'notes': _notesController.text.trim().isEmpty 
            ? null 
            : _notesController.text.trim(),
      };

      final paymentResponse = await Supabase.instance.client
          .from('purchase_payments')
          .insert(paymentData)
          .select()
          .single();

      final paymentId = paymentResponse['id'];

      // Create journal entry for payment
      await _createPaymentJournalEntry(paymentId, amount);

      // Update invoice paid_amount and balance
      final newPaidAmount = widget.invoice.paidAmount + amount;
      final newBalance = widget.invoice.total - newPaidAmount;
      final newStatus = newBalance <= 0.01 ? 'paid' : widget.invoice.status.name;

      await Supabase.instance.client
          .from('purchase_invoices')
          .update({
            'paid_amount': newPaidAmount,
            'balance': newBalance,
            'status': newStatus,
            if (newStatus == 'paid') 'paid_date': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.invoiceId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pago registrado: ${ChileanUtils.formatCurrency(amount)}'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar pago: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _createPaymentJournalEntry(String paymentId, double amount) async {
    // Get AP account (2120)
    final apAccount = await Supabase.instance.client
        .from('accounts')
        .select()
        .eq('code', '2120')
        .single();

    // Create journal entry
    final journalData = {
      'date': _paymentDate.toIso8601String(),
      'description': 'Pago de factura ${widget.invoice.invoiceNumber}',
      'reference': 'PAGO-${widget.invoice.invoiceNumber}',
      'entry_type': 'manual',
    };

    final journalResponse = await Supabase.instance.client
        .from('journal_entries')
        .insert(journalData)
        .select()
        .single();

    final journalEntryId = journalResponse['id'];

    // Create journal lines
    final lines = [
      {
        'journal_entry_id': journalEntryId,
        'account_id': apAccount['id'],
        'debit': amount,
        'credit': 0.0,
        'description': 'Pago a proveedor ${widget.invoice.supplierName}',
      },
      {
        'journal_entry_id': journalEntryId,
        'account_id': _selectedBankAccount,
        'debit': 0.0,
        'credit': amount,
        'description': 'Pago de factura ${widget.invoice.invoiceNumber}',
      },
    ];

    await Supabase.instance.client
        .from('journal_entry_lines')
        .insert(lines);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Pago'),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _isLoadingAccounts
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInvoiceInfo(),
                    const SizedBox(height: 24),
                    _buildPaymentForm(),
                    const SizedBox(height: 32),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInvoiceInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Factura ${widget.invoice.invoiceNumber}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.invoice.supplierName != null)
              Text(
                widget.invoice.supplierName!,
                style: const TextStyle(color: Colors.grey),
              ),
            const Divider(height: 24),
            _buildInfoRow('Total', ChileanUtils.formatCurrency(widget.invoice.total)),
            _buildInfoRow('Pagado', ChileanUtils.formatCurrency(widget.invoice.paidAmount)),
            _buildInfoRow(
              'Saldo',
              ChileanUtils.formatCurrency(widget.invoice.balance),
              highlight: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              fontSize: highlight ? 18 : 14,
              color: highlight ? Colors.blue : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detalles del Pago',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Payment Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Fecha de Pago'),
              subtitle: Text(ChileanUtils.formatDate(_paymentDate)),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _paymentDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) {
                  setState(() => _paymentDate = picked);
                }
              },
            ),
            const Divider(),

            // Payment Amount
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Monto *',
                prefixText: '\$ ',
                hintText: '0',
                helperText: 'Ingrese el monto del pago',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'El monto es requerido';
                }
                final amount = double.tryParse(value.replaceAll('.', ''));
                if (amount == null || amount <= 0) {
                  return 'Ingrese un monto válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Payment Method
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Método de Pago *',
                prefixIcon: Icon(Icons.payment),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
                DropdownMenuItem(value: 'check', child: Text('Cheque')),
                DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                DropdownMenuItem(value: 'other', child: Text('Otro')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _paymentMethod = value);
                }
              },
            ),
            const SizedBox(height: 16),

            // Bank Account
            if (_bankAccounts.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'No hay cuentas bancarias disponibles. '
                        'Cree una cuenta de tipo Activo con código 11xx.',
                      ),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedBankAccount,
                decoration: const InputDecoration(
                  labelText: 'Cuenta Bancaria *',
                  prefixIcon: Icon(Icons.account_balance),
                ),
                items: _bankAccounts.map((account) {
                  return DropdownMenuItem<String>(
                    value: account['id'].toString(),
                    child: Text('${account['code']} - ${account['name']}'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedBankAccount = value);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Seleccione una cuenta bancaria';
                  }
                  return null;
                },
              ),
            const SizedBox(height: 16),

            // Reference
            TextFormField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Referencia',
                hintText: 'Ej: Transferencia #12345',
                prefixIcon: Icon(Icons.numbers),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 8),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notas',
                hintText: 'Observaciones adicionales',
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => context.pop(false),
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _savePayment,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(_isSaving ? 'Guardando...' : 'Registrar Pago'),
          ),
        ),
      ],
    );
  }
}
