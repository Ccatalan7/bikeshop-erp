import sys

try:
    with open('/Users/Claudio/Dev/bikeshop-erp/lib/modules/pos/pages/pos_dashboard_page.dart', 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    def get_method_bounds(method_name):
        start_idx = -1
        for i, line in enumerate(lines):
            if line.startswith(f"  Widget {method_name}("):
                start_idx = i
                break
                
        if start_idx == -1: return -1, -1
        
        open_braces = 0
        in_method = False
        for i in range(start_idx, len(lines)):
            line = lines[i]
            open_braces += line.count('{')
            open_braces -= line.count('}')
            if open_braces > 0:
                in_method = True
            
            if in_method and open_braces == 0:
                return start_idx, i
        return -1, -1

    piv_s, piv_e = get_method_bounds('_buildPendingInvoicesView')
    print(f"Pending Invoices bounds: {piv_s} to {piv_e}")

    ip_s, ip_e = get_method_bounds('_buildInvoicePaymentForm')
    print(f"Invoice Payment bounds: {ip_s} to {ip_e}")

    if piv_s == -1 or ip_s == -1:
        print("Could not find method bounds")
        sys.exit(1)

    pending_invoices_new = """  Widget _buildPendingInvoicesView(ThemeData theme, POSService posService) {
    final currencyFormat = NumberFormat.currency(symbol: '\\$', decimalDigits: 0);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Column(
      children: [
        // ── Header (fixed top) ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.inventory_2_rounded,
                  color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Facturas Pendientes',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      _selectedCustomer?.name ?? '',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Invoices List (scrollable middle) ───────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: _pendingInvoices.map((invoice) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      posService.enterInvoicePaymentMode(invoice);
                      setState(() {
                        _showPendingInvoices = false;
                        if (_paymentAmountController.text.isEmpty) {
                          _paymentAmountController.text =
                              invoice.balance.toStringAsFixed(0);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                invoice.invoiceNumber,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  invoice.status.name.toUpperCase(),
                                  style: TextStyle(
                                    color: theme.colorScheme.onErrorContainer,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                dateFormat.format(invoice.date),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (invoice.reference != null && invoice.reference!.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.tag_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  invoice.reference!,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Total Factura', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 2),
                                  Text(
                                    currencyFormat.format(invoice.total),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Saldo Pendiente', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 2),
                                  Text(
                                    currencyFormat.format(invoice.balance),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ── Action (fixed bottom) ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _continueWithNormalSale,
              icon: const Icon(Icons.shopping_cart_outlined, size: 20),
              label: const Text(
                'Continuar Venta Normal',
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }"""

    invoice_payment_new = """  Widget _buildInvoicePaymentForm(ThemeData theme, POSService posService) {
    final invoice = posService.linkedInvoice!;
    final currencyFormat = NumberFormat.currency(symbol: '\\$', decimalDigits: 0);

    return Column(
      children: [
        // ── Header (fixed top) ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                onPressed: () {
                  posService.exitInvoicePaymentMode();
                  setState(() => _showPendingInvoices = true);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Abonar a Factura',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      invoice.invoiceNumber,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Form Content (scrollable middle) ────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Financial Info Box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildSummaryRow(theme, 'Cliente', invoice.customerName ?? 'Sin nombre', valueColor: theme.colorScheme.onSurface),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                      _buildSummaryRow(theme, 'Total Factura', currencyFormat.format(invoice.total), valueColor: theme.colorScheme.onSurface),
                      if (invoice.paidAmount > 0) ...[
                        const SizedBox(height: 6),
                        _buildSummaryRow(theme, 'Pagado', currencyFormat.format(invoice.paidAmount), valueColor: theme.colorScheme.tertiary),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Deuda',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              currencyFormat.format(invoice.balance),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Amount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Monto a Pagar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _paymentAmountController.text = invoice.balance.toStringAsFixed(0);
                        });
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                      label: const Text('Completar Total'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paymentAmountController,
                  keyboardType: TextInputType.number,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    prefixText: '\\$ ',
                    prefixStyle: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),

                // Payment Method Selector
                Text(
                  'Método de Pago',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Consumer<PaymentMethodService>(
                  builder: (context, paymentMethodService, _) {
                    final methods = paymentMethodService.paymentMethods;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: methods.map((method) {
                        final isSelected = _selectedPaymentMethodId == method.id;
                        return FilterChip(
                          showCheckmark: false,
                          selected: isSelected,
                          label: Text(
                            method.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          onSelected: (selected) {
                            if (selected) setState(() => _selectedPaymentMethodId = method.id);
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Reference
                TextField(
                  controller: _paymentReferenceController,
                  decoration: InputDecoration(
                    labelText: 'Referencia (Opcional)',
                    hintText: 'Nº transferencia, cheque, etc.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Action Buttons (fixed bottom) ──────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: _selectedPaymentMethodId != null && !_isProcessing
                  ? () => _processInvoicePayment(posService, invoice)
                  : null,
              icon: _isProcessing
                  ? Container(
                      width: 20,
                      height: 20,
                      padding: const EdgeInsets.all(2),
                      child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.payment_rounded, size: 20),
              label: Text(
                _isProcessing ? 'Procesando...' : 'Registrar Pago',
                style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }"""

    # Do the replacements safely from bottom to top so indices don't shift
    pre_piv = lines[:piv_s]
    post_piv = lines[piv_e+1:ip_s]
    post_ip = lines[ip_e+1:]

    new_content = ''.join(pre_piv) + pending_invoices_new + "\n" + ''.join(post_piv) + invoice_payment_new + "\n" + ''.join(post_ip)

    with open('/Users/Claudio/Dev/bikeshop-erp/lib/modules/pos/pages/pos_dashboard_page.dart', 'w', encoding='utf-8') as f:
        f.write(new_content)
        
    print("Replacements completed successfully")

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
