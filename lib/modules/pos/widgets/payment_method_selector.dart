import 'package:flutter/material.dart';
import '../models/payment_method.dart';

class PaymentMethodSelector extends StatelessWidget {
  final List<PaymentMethod> paymentMethods;
  final PaymentMethod? selectedMethod;
  final ValueChanged<PaymentMethod>? onMethodSelected;
  final double? amount;
  final ValueChanged<double>? onAmountChanged;
  final bool showAmountInput;

  const PaymentMethodSelector({
    super.key,
    required this.paymentMethods,
    this.selectedMethod,
    this.onMethodSelected,
    this.amount,
    this.onAmountChanged,
    this.showAmountInput = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Payment method grid (without duplicate label)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: paymentMethods.length,
          itemBuilder: (context, index) {
            final method = paymentMethods[index];
            final isSelected = selectedMethod?.id == method.id;
            
            return InkWell(
              onTap: () => onMethodSelected?.call(method),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    width: isSelected ? 2 : 1,
                  ),
                  color: isSelected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surface,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getPaymentMethodIcon(method.type),
                      color: isSelected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      method.name,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                        fontWeight: isSelected ? FontWeight.bold : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        
        // Amount input (without duplicate label - controlled by parent page)
        if (showAmountInput && selectedMethod != null) ...[
          const SizedBox(height: 16),
          
          TextFormField(
            initialValue: amount?.toStringAsFixed(0),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Ingrese el monto',
              prefixText: '\$ ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: selectedMethod!.requiresChange
                  ? const Icon(Icons.money)
                  : null,
            ),
            onChanged: (value) {
              final parsedAmount = double.tryParse(value);
              if (parsedAmount != null) {
                onAmountChanged?.call(parsedAmount);
              }
            },
          ),
          
          // Change calculation for cash payments
          if (selectedMethod!.requiresChange && amount != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Vuelto:',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    '\$${(amount! - (onAmountChanged != null ? 0 : 0)).toStringAsFixed(0)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  IconData _getPaymentMethodIcon(PaymentType type) {
    switch (type) {
      case PaymentType.cash:
        return Icons.attach_money;
      case PaymentType.card:
        return Icons.credit_card;
      case PaymentType.voucher:
        return Icons.receipt;
      case PaymentType.transfer:
        return Icons.account_balance;
    }
  }
}