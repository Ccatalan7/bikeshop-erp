import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/payment_method.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/services/tenant_service.dart';
import '../../accounting/services/accounting_service.dart';

class PaymentMethodsSettingsPage extends StatefulWidget {
  final bool embedded;

  const PaymentMethodsSettingsPage({super.key, this.embedded = false});

  @override
  State<PaymentMethodsSettingsPage> createState() =>
      _PaymentMethodsSettingsPageState();
}

class _PaymentMethodsSettingsPageState
    extends State<PaymentMethodsSettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentMethodService>().loadPaymentMethods(forceRefresh: true);
      context.read<AccountingService>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = Consumer<PaymentMethodService>(
        builder: (context, service, child) {
          if (service.isLoading) {
            return const Center(child: BrandedLoading());
          }

          if (service.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(service.error!, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => service.refresh(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          if (service.paymentMethods.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payment, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    'No hay métodos de pago configurados',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Agrega el primer método de pago'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showPaymentMethodDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar Método de Pago'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // In embedded mode, keep an obvious "Add" action since the AppBar is provided by the overlay.
              if (widget.embedded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () => _showPaymentMethodDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: service.paymentMethods.length,
                  itemBuilder: (context, index) {
                    final method = service.paymentMethods[index];
                    return _buildPaymentMethodCard(context, method);
                  },
                ),
              ),
            ],
          );
        },
      );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Métodos de Pago'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showPaymentMethodDialog(context),
            tooltip: 'Agregar método de pago',
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildPaymentMethodCard(BuildContext context, PaymentMethod method) {
    final theme = Theme.of(context);
    final accountingService = context.watch<AccountingService>();
    final account = accountingService.accounts.firstWhere(
      (a) => a.id == method.accountId,
      orElse: () => accountingService.accounts.first,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            _getIconData(method.icon ?? 'payment'),
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(
          method.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Código: ${method.code}'),
            Text('Cuenta: ${account.code} - ${account.name}'),
            if (method.requiresReference)
              const Text(
                'Requiere referencia',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            PopupMenuItem(
              child: const Row(
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text('Editar'),
                ],
              ),
              onTap: () {
                Future.delayed(
                  Duration.zero,
                  () => _showPaymentMethodDialog(context, method: method),
                );
              },
            ),
            PopupMenuItem(
              child: Row(
                children: [
                  Icon(
                    method.isActive ? Icons.toggle_off : Icons.toggle_on,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(method.isActive ? 'Desactivar' : 'Activar'),
                ],
              ),
              onTap: () => _toggleActive(context, method),
            ),
            PopupMenuItem(
              child: const Row(
                children: [
                  Icon(Icons.delete, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Eliminar', style: TextStyle(color: Colors.red)),
                ],
              ),
              onTap: () => _deletePaymentMethod(context, method),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'cash':
        return Icons.money;
      case 'bank':
        return Icons.account_balance;
      case 'card':
        return Icons.credit_card;
      case 'receipt':
        return Icons.receipt;
      default:
        return Icons.payment;
    }
  }

  void _showPaymentMethodDialog(BuildContext context, {PaymentMethod? method}) {
    showDialog(
      context: context,
      builder: (context) => _PaymentMethodDialog(method: method),
    );
  }

  void _toggleActive(BuildContext context, PaymentMethod method) async {
    final service = context.read<PaymentMethodService>();
    final updated = method.copyWith(isActive: !method.isActive);
    final result = await service.updatePaymentMethod(updated);

    if (!mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            method.isActive ? 'Método desactivado' : 'Método activado',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al cambiar estado del método'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deletePaymentMethod(BuildContext context, PaymentMethod method) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Eliminar el método de pago "${method.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final service = context.read<PaymentMethodService>();
    final success = await service.deactivatePaymentMethod(method.id);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Método desactivado')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al desactivar método'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _PaymentMethodDialog extends StatefulWidget {
  final PaymentMethod? method;

  const _PaymentMethodDialog({this.method});

  @override
  State<_PaymentMethodDialog> createState() => _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends State<_PaymentMethodDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeController;
  late TextEditingController _nameController;
  late int _sortOrder;
  late bool _requiresReference;
  late bool _isActive;
  late TaxTreatment _defaultTaxTreatment;
  String? _selectedAccountId;
  String _selectedIcon = 'payment';

  final List<Map<String, dynamic>> _availableIcons = [
    {'value': 'cash', 'label': 'Efectivo', 'icon': Icons.money},
    {'value': 'bank', 'label': 'Banco', 'icon': Icons.account_balance},
    {'value': 'credit_card', 'label': 'Tarjeta', 'icon': Icons.credit_card},
    {'value': 'receipt', 'label': 'Cheque', 'icon': Icons.receipt},
    {'value': 'payment', 'label': 'Genérico', 'icon': Icons.payment},
  ];

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.method?.code ?? '');
    _nameController = TextEditingController(text: widget.method?.name ?? '');
    _sortOrder = widget.method?.sortOrder ?? 99;
    _requiresReference = widget.method?.requiresReference ?? false;
    _isActive = widget.method?.isActive ?? true;
    _defaultTaxTreatment = widget.method?.defaultTaxTreatment ?? TaxTreatment.noTax;
    _selectedAccountId = widget.method?.accountId;
    _selectedIcon = widget.method?.icon ?? 'payment';

    // Load accounts if not loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccountingService>().initialize();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.method == null ? 'Nuevo Método de Pago' : 'Editar Método'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 500,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Code
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Código *',
                    hintText: 'ej: cash, card, transfer',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'El código es requerido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    hintText: 'ej: Efectivo, Tarjeta de Crédito',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'El nombre es requerido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Icon selector
                DropdownButtonFormField<String>(
                  initialValue: _selectedIcon,
                  decoration: const InputDecoration(
                    labelText: 'Icono',
                    border: OutlineInputBorder(),
                  ),
                  items: _availableIcons.map((item) {
                    return DropdownMenuItem<String>(
                      value: item['value'] as String,
                      child: Row(
                        children: [
                          Icon(item['icon'] as IconData, size: 20),
                          const SizedBox(width: 8),
                          Text(item['label'] as String),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedIcon = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Account selector
                Consumer<AccountingService>(
                  builder: (context, accountingService, child) {
                    if (accountingService.accounts.isEmpty) {
                      return const LinearProgressIndicator();
                    }

                    // Filter to cash/bank accounts (1xxx - Assets)
                    final cashAndBankAccounts = accountingService.accounts
                        .where((a) => a.code.startsWith('1'))
                        .toList();

                    return DropdownButtonFormField<String>(
                      initialValue: _selectedAccountId,
                      decoration: const InputDecoration(
                        labelText: 'Cuenta Contable *',
                        border: OutlineInputBorder(),
                        helperText: 'Cuenta donde se registran los cobros',
                      ),
                      items: cashAndBankAccounts.map((account) {
                        return DropdownMenuItem<String>(
                          value: account.id,
                          child: Text('${account.code} - ${account.name}'),
                        );
                      }).toList(),
                      validator: (value) {
                        if (value == null) {
                          return 'Selecciona una cuenta';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        setState(() => _selectedAccountId = value);
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Tax treatment dropdown
                DropdownButtonFormField<TaxTreatment>(
                  initialValue: _defaultTaxTreatment,
                  decoration: const InputDecoration(
                    labelText: 'Tratamiento de IVA por Defecto',
                    border: OutlineInputBorder(),
                    helperText: 'Sugerencia de IVA al seleccionar este método',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: TaxTreatment.noTax,
                      child: Row(
                        children: [
                          Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          const Text('Sin IVA'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: TaxTreatment.taxIncluded,
                      child: Row(
                        children: [
                          Icon(Icons.percent, size: 20, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          const Text('IVA Incluido (19%)'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _defaultTaxTreatment = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Sort order
                TextFormField(
                  initialValue: _sortOrder.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Orden de Visualización',
                    hintText: '1, 2, 3...',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _sortOrder = int.tryParse(value) ?? 99;
                  },
                ),
                const SizedBox(height: 16),

                // Checkboxes
                CheckboxListTile(
                  value: _requiresReference,
                  onChanged: (value) {
                    setState(() => _requiresReference = value ?? false);
                  },
                  title: const Text('Requiere Referencia'),
                  subtitle: const Text('Ej: Nº cheque, Nº transferencia'),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: _isActive,
                  onChanged: (value) {
                    setState(() => _isActive = value ?? true);
                  },
                  title: const Text('Activo'),
                  subtitle: const Text('Visible en formularios de pago'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final service = context.read<PaymentMethodService>();
    final tenantService = TenantService();
    final tenantId = await tenantService.getTenantId();

    if (tenantId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No se pudo obtener el tenant_id'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final method = PaymentMethod(
      id: widget.method?.id ?? '',
      tenantId: widget.method?.tenantId ?? tenantId,
      code: _codeController.text.trim(),
      name: _nameController.text.trim(),
      accountId: _selectedAccountId!,
      requiresReference: _requiresReference,
      defaultTaxTreatment: _defaultTaxTreatment,
      icon: _selectedIcon,
      sortOrder: _sortOrder,
      isActive: _isActive,
    );

    PaymentMethod? result;
    if (widget.method == null) {
      result = await service.createPaymentMethod(method);
    } else {
      result = await service.updatePaymentMethod(method);
    }

    if (!mounted) return;

    if (result != null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.method == null
                ? 'Método creado correctamente'
                : 'Método actualizado correctamente',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al guardar el método'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
