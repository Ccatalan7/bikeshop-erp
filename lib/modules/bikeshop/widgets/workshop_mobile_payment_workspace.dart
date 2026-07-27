import 'package:flutter/material.dart';

import '../../sales/models/sales_models.dart';

/// Compact host for the canonical sales payment form inside the Jobs workspace.
///
/// This widget owns only composition and return navigation. The supplied
/// [paymentForm] remains the canonical owner of validation and persistence.
class WorkshopMobilePaymentWorkspace extends StatelessWidget {
  const WorkshopMobilePaymentWorkspace({
    super.key,
    required this.invoice,
    required this.onBack,
    required this.paymentForm,
  });

  final Invoice invoice;
  final VoidCallback onBack;
  final Widget paymentForm;

  String get _invoiceIdentity {
    final invoiceNumber = invoice.invoiceNumber.trim();
    return invoiceNumber.isEmpty
        ? 'Factura sin número'
        : 'Factura $invoiceNumber';
  }

  String get _subtitle {
    final customerName = invoice.customerName?.trim();
    if (customerName == null || customerName.isEmpty) {
      return _invoiceIdentity;
    }
    return '$_invoiceIdentity · $customerName';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          onBack();
        }
      },
      child: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: Material(
          color: colorScheme.surface,
          child: Column(
            children: [
              Container(
                key: const ValueKey('workshop-payment-header'),
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Volver a $_invoiceIdentity',
                      excludeSemantics: true,
                      child: TextButton.icon(
                        key: const ValueKey('workshop-payment-back'),
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        label: const Text('Factura'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        container: true,
                        header: true,
                        label: 'Registrar abono. $_subtitle',
                        excludeSemantics: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Registrar abono',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding =
                        constraints.maxWidth < 600 ? 12.0 : 20.0;
                    return SingleChildScrollView(
                      key: const ValueKey('workshop-payment-scroll'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        16,
                        horizontalPadding,
                        24 + keyboardInset,
                      ),
                      child: SizedBox(
                        key: const ValueKey('workshop-payment-form-host'),
                        width: double.infinity,
                        child: paymentForm,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
