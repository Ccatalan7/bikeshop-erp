import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/account.dart';
import '../models/journal_entry.dart';
import '../services/accounting_service.dart';

class JournalEntryFormPage extends StatefulWidget {
  final String? entryId;

  const JournalEntryFormPage({super.key, this.entryId});

  @override
  State<JournalEntryFormPage> createState() => _JournalEntryFormPageState();
}

class _JournalEntryFormPageState extends State<JournalEntryFormPage> {
  final _formKey = GlobalKey<FormState>();
  late AccountingService _accountingService;
  
  // Form controllers
  final _dateController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  // State
  DateTime _selectedDate = DateTime.now();
  JournalEntryType _selectedType = JournalEntryType.manual;
  List<JournalLineForm> _lines = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  
  // Account cache
  List<Account> _accounts = [];
  
  // Formatting
  final DateFormat _dateFormat = ChileanUtils.dateFormat;
  final NumberFormat _currencyFormat = ChileanUtils.currencyFormat;

  @override
  void initState() {
    super.initState();
    _accountingService = Provider.of<AccountingService>(context, listen: false);
    _dateController.text = _dateFormat.format(_selectedDate);
    
    // Add initial empty lines
    _addEmptyLine();
    _addEmptyLine();
    
    // Delay the load to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAccounts();
    });
  }

  @override
  void dispose() {
    _dateController.dispose();
    _descriptionController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    
    try {
      final accounts = await _accountingService.getAccounts();
      setState(() {
        _accounts = accounts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _addEmptyLine() {
    setState(() {
      _lines.add(JournalLineForm(_accounts));
    });
  }

  void _removeLine(int index) {
    if (_lines.length > 2) {
      setState(() {
        _lines[index].dispose();
        _lines.removeAt(index);
      });
    }
  }

  double get _totalDebits {
    return _lines.fold(0.0, (sum, line) => sum + line.debitAmount);
  }

  double get _totalCredits {
    return _lines.fold(0.0, (sum, line) => sum + line.creditAmount);
  }

  bool get _isBalanced {
    return (_totalDebits - _totalCredits).abs() < 0.01;
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'CL'),
    );
    
    if (date != null) {
      setState(() {
        _selectedDate = date;
        _dateController.text = _dateFormat.format(date);
      });
    }
  }

  Future<void> _saveJournalEntry() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_isBalanced) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El asiento contable debe estar balanceado (Debe = Haber)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate that all lines have accounts and amounts
    final validLines = _lines.where((line) => 
      line.selectedAccount != null && line.totalAmount > 0
    ).toList();

    if (validLines.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El asiento debe tener al menos 2 líneas válidas'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final journalLines = validLines.map((lineForm) => JournalLine(
        accountId: lineForm.selectedAccount!.id!,
        accountCode: lineForm.selectedAccount!.code,
        accountName: lineForm.selectedAccount!.name,
        description: lineForm.descriptionController.text.trim().isEmpty 
            ? _descriptionController.text 
            : lineForm.descriptionController.text,
        debitAmount: lineForm.debitAmount,
        creditAmount: lineForm.creditAmount,
        createdAt: DateTime.now(),
      )).toList();

      await _accountingService.createJournalEntry(
        date: _selectedDate,
        description: _descriptionController.text,
        type: _selectedType,
        lines: journalLines,
        sourceModule: 'Manual',
        sourceReference: null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Asiento contable creado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear asiento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Nuevo Asiento Contable',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Header form
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
                              child: TextFormField(
                                controller: _dateController,
                                decoration: InputDecoration(
                                  labelText: 'Fecha *',
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.calendar_today),
                                    onPressed: _selectDate,
                                  ),
                                ),
                                readOnly: true,
                                validator: (value) => value?.isEmpty == true 
                                    ? 'La fecha es requerida' 
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<JournalEntryType>(
                                decoration: const InputDecoration(
                                  labelText: 'Tipo *',
                                  border: OutlineInputBorder(),
                                ),
                                value: _selectedType,
                                items: JournalEntryType.values.map((type) =>
                                  DropdownMenuItem<JournalEntryType>(
                                    value: type,
                                    child: Text(type.displayName),
                                  ),
                                ).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _selectedType = value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Descripción *',
                            border: OutlineInputBorder(),
                            hintText: 'Descripción del asiento contable',
                          ),
                          maxLines: 2,
                          validator: (value) => value?.trim().isEmpty == true 
                              ? 'La descripción es requerida' 
                              : null,
                        ),
                      ],
                    ),
                  ),
                  
                  // Lines section
                  Expanded(
                    child: Column(
                      children: [
                        // Lines header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border(
                              bottom: BorderSide(color: Theme.of(context).dividerColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                flex: 3,
                                child: Text('Cuenta', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const Expanded(
                                flex: 3,
                                child: Text('Descripción', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const Expanded(
                                flex: 2,
                                child: Text('Debe', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                flex: 2,
                                child: Text('Haber', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                              ),
                              const SizedBox(width: 48), // Space for delete button
                            ],
                          ),
                        ),
                        
                        // Lines list
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _lines.length,
                            itemBuilder: (context, index) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Theme.of(context).dividerColor),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _lines[index].buildAccountSelector(),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      flex: 3,
                                      child: _lines[index].buildDescriptionField(),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      flex: 2,
                                      child: _lines[index].buildDebitField(),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      flex: 2,
                                      child: _lines[index].buildCreditField(),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: _lines.length > 2 
                                          ? () => _removeLine(index)
                                          : null,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Footer with totals and actions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border(
                        top: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Totals
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _isBalanced 
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isBalanced ? Colors.green : Colors.red,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isBalanced ? Icons.check_circle : Icons.error,
                                color: _isBalanced ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isBalanced ? 'Asiento balanceado' : 'Asiento desbalanceado',
                                style: TextStyle(
                                  color: _isBalanced ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Debe: ${_currencyFormat.format(_totalDebits)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 32),
                              Text(
                                'Haber: ${_currencyFormat.format(_totalCredits)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Actions
                        Row(
                          children: [
                            AppButton(
                              text: 'Agregar Línea',
                              onPressed: _addEmptyLine,
                              icon: Icons.add,
                              type: ButtonType.secondary,
                            ),
                            const Spacer(),
                            AppButton(
                              text: 'Cancelar',
                              onPressed: () => context.pop(),
                              type: ButtonType.outline,
                            ),
                            const SizedBox(width: 16),
                            AppButton(
                              text: _isSaving ? 'Guardando...' : 'Guardar Asiento',
                              onPressed: _isSaving ? null : _saveJournalEntry,
                              icon: _isSaving ? null : Icons.save,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class JournalLineForm {
  final List<Account> accounts;
  Account? selectedAccount;
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController debitController = TextEditingController();
  final TextEditingController creditController = TextEditingController();
  final TextEditingController accountSearchController = TextEditingController();
  
  bool _showAccountDropdown = false;
  List<Account> _filteredAccounts = [];

  JournalLineForm(this.accounts) {
    _filteredAccounts = accounts;
  }

  void dispose() {
    descriptionController.dispose();
    debitController.dispose();
    creditController.dispose();
    accountSearchController.dispose();
  }

  double get debitAmount {
    final text = debitController.text.replaceAll(',', '').replaceAll('\$', '');
    return double.tryParse(text) ?? 0.0;
  }

  double get creditAmount {
    final text = creditController.text.replaceAll(',', '').replaceAll('\$', '');
    return double.tryParse(text) ?? 0.0;
  }

  double get totalAmount => debitAmount + creditAmount;

  Widget buildAccountSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: accountSearchController,
          decoration: InputDecoration(
            labelText: 'Cuenta *',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_showAccountDropdown ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
              onPressed: () {
                _showAccountDropdown = !_showAccountDropdown;
              },
            ),
          ),
          onChanged: (value) {
            _filteredAccounts = accounts.where((account) =>
              account.code.toLowerCase().contains(value.toLowerCase()) ||
              account.name.toLowerCase().contains(value.toLowerCase())
            ).toList();
          },
          onTap: () {
            _showAccountDropdown = true;
          },
          readOnly: selectedAccount != null,
        ),
        if (_showAccountDropdown && selectedAccount == null)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredAccounts.length,
              itemBuilder: (context, index) {
                final account = _filteredAccounts[index];
                return ListTile(
                  title: Text('${account.code} - ${account.name}'),
                  subtitle: Text(account.type.displayName),
                  onTap: () {
                    selectedAccount = account;
                    accountSearchController.text = '${account.code} - ${account.name}';
                    _showAccountDropdown = false;
                  },
                );
              },
            ),
          ),
        if (selectedAccount != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${selectedAccount!.code} - ${selectedAccount!.name}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  selectedAccount = null;
                  accountSearchController.clear();
                },
              ),
            ],
          ),
      ],
    );
  }

  Widget buildDescriptionField() {
    return TextFormField(
      controller: descriptionController,
      decoration: const InputDecoration(
        labelText: 'Descripción',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget buildDebitField() {
    return TextFormField(
      controller: debitController,
      decoration: const InputDecoration(
        labelText: 'Debe',
        border: OutlineInputBorder(),
        prefixText: '\$ ',
      ),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      onChanged: (value) {
        if (value.isNotEmpty) {
          creditController.clear();
        }
      },
    );
  }

  Widget buildCreditField() {
    return TextFormField(
      controller: creditController,
      decoration: const InputDecoration(
        labelText: 'Haber',
        border: OutlineInputBorder(),
        prefixText: '\$ ',
      ),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      onChanged: (value) {
        if (value.isNotEmpty) {
          debitController.clear();
        }
      },
    );
  }
}