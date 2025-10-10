import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../services/pos_service.dart';
import '../models/payment_method.dart';
import '../models/pos_transaction.dart';
import '../widgets/payment_method_selector.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';

class POSPaymentPage extends StatefulWidget {
  const POSPaymentPage({super.key});

  @override
  State<POSPaymentPage> createState() => _POSPaymentPageState();
}

class _POSPaymentPageState extends State<POSPaymentPage> {
  PaymentMethod? _selectedPaymentMethod;
  double _amountReceived = 0.0;
  bool _isProcessing = false;
  final Uuid _uuid = const Uuid();
  
  Customer? _selectedCustomer;
  List<Customer> _customers = [];
  bool _isLoadingCustomers = true;
  final TextEditingController _customerSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Set default payment method to cash
    _selectedPaymentMethod = PaymentMethod.cash;
    
    // Set default amount to the total
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final posService = context.read<POSService>();
      setState(() {
        _amountReceived = posService.cartTotal;
      });
    });
    
    // Load customers
    _loadCustomers();
  }

  @override
  void dispose() {
    _customerSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customerService = Provider.of<CustomerService>(context, listen: false);
      final customers = await customerService.getCustomers();
      
      if (mounted) {
        setState(() {
          _customers = customers;
          _isLoadingCustomers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCustomers = false;
        });
      }
    }
  }

  Future<void> _processPayment() async {
    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione un método de pago')),
      );
      return;
    }

    final posService = context.read<POSService>();
    
    if (_amountReceived < posService.cartTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monto insuficiente')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Create payment
      final payment = POSPayment(
        id: _uuid.v4(),
        method: _selectedPaymentMethod!,
        amount: _amountReceived,
        createdAt: DateTime.now(),
      );
      
      // Process the payment
      final transaction = await posService.checkout([payment]);

      if (mounted && transaction != null) {
        // Navigate to receipt
        context.pushReplacement('/pos/receipt', extra: transaction);
      } else {
        throw Exception('Failed to process transaction');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar pago: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  'Procesar Pago',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Content area
        Expanded(
          child: Consumer<POSService>(
            builder: (context, posService, child) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order summary
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resumen del Pedido',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Subtotal:', style: theme.textTheme.bodyLarge),
                                Text('\$${posService.cartNetAmount.toStringAsFixed(0)}'),
                              ],
                            ),
                            
                            if (posService.cartDiscountAmount > 0)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Descuento:', style: theme.textTheme.bodyLarge),
                                  Text(
                                    '-\$${posService.cartDiscountAmount.toStringAsFixed(0)}',
                                    style: TextStyle(color: theme.colorScheme.error),
                                  ),
                                ],
                              ),
                            
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('IVA (19%):', style: theme.textTheme.bodyLarge),
                                Text('\$${posService.cartTaxAmount.toStringAsFixed(0)}'),
                              ],
                            ),
                            
                            const Divider(),
                            
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'TOTAL:',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '\$${posService.cartTotal.toStringAsFixed(0)}',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Customer selector
                    Text(
                      'Cliente',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    if (_isLoadingCustomers)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      )
                    else
                      DropdownButtonFormField<Customer>(
                        value: _selectedCustomer,
                        decoration: const InputDecoration(
                          labelText: 'Seleccionar Cliente (Opcional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<Customer>(
                            value: null,
                            child: Text('Cliente Genérico'),
                          ),
                          ..._customers.map((customer) {
                            final identifier = customer.rut.isNotEmpty
                                ? customer.rut
                                : (customer.email ?? 'Sin RUT');
                            return DropdownMenuItem<Customer>(
                              value: customer,
                              child: Text('${customer.name} - $identifier'),
                            );
                          }).toList(),
                        ],
                        onChanged: (customer) {
                          setState(() {
                            _selectedCustomer = customer;
                          });
                        },
                      ),
                    
                    const SizedBox(height: 24),
                    
                    // Payment method selector
                    Text(
                      'Método de Pago',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    PaymentMethodSelector(
                      paymentMethods: PaymentMethod.defaultMethods,
                      selectedMethod: _selectedPaymentMethod,
                      onMethodSelected: (method) {
                        setState(() {
                          _selectedPaymentMethod = method;
                          if (method != PaymentMethod.cash) {
                            _amountReceived = posService.cartTotal;
                          }
                        });
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Amount received (only for cash)
                    if (_selectedPaymentMethod == PaymentMethod.cash) ...[
                      Text(
                        'Monto Recibido',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      TextField(
                        onChanged: (value) {
                          setState(() {
                            _amountReceived = double.tryParse(value) ?? 0.0;
                          });
                        },
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Monto en efectivo',
                          prefixText: '\$',
                          border: const OutlineInputBorder(),
                          hintText: posService.cartTotal.toStringAsFixed(0),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Change calculation
                      if (_amountReceived >= posService.cartTotal)
                        Card(
                          color: theme.colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Vuelto:',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                Text(
                                  '\$${(_amountReceived - posService.cartTotal).toStringAsFixed(0)}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      
                      const SizedBox(height: 24),
                    ],
                    
                    // Payment button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isProcessing ? null : _processPayment,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: Text(_isProcessing ? 'Procesando...' : 'Confirmar Pago'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}