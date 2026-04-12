import re

with open('/Users/Claudio/Dev/bikeshop-erp/lib/modules/pos/pages/pos_dashboard_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

replacement = """  Widget _buildCartView(
      ThemeData theme, POSService posService, String currentQuery) {
    // Show pending invoices list if customer has pending invoices
    if (_showPendingInvoices) {
      return _buildPendingInvoicesView(theme, posService);
    }

    // Show invoice payment form if in payment mode
    if (posService.isInvoicePaymentMode && posService.linkedInvoice != null) {
      return _buildInvoicePaymentForm(theme, posService);
    }

    final hasItems = posService.cartItems.isNotEmpty;
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Column(
      children: [
        // ── Customer section (fixed top) ─────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline_rounded,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Cliente',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isLoadingCustomers)
                const SizedBox(
                    height: 36, child: LinearProgressIndicator())
              else
                DropdownButtonFormField<Customer>(
                  value: _selectedCustomer,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  isExpanded: true,
                  hint: const Text('Cliente Genérico'),
                  items: [
                    const DropdownMenuItem<Customer>(
                      value: null,
                      child: Text('Cliente Genérico'),
                    ),
                    ..._filteredCustomers.map((customer) {
                      return DropdownMenuItem<Customer>(
                        value: customer,
                        child: Text(
                          customer.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                    if (_selectedCustomer != null &&
                        !_filteredCustomers
                            .any((c) => c.id == _selectedCustomer!.id))
                      DropdownMenuItem<Customer>(
                        value: _selectedCustomer,
                        child: Text(_selectedCustomer!.name,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (customer) async {
                    setState(() => _selectedCustomer = customer);
                    context.read<POSService>().setCustomer(customer);
                    if (customer != null) {
                      await _checkPendingInvoices(customer);
                    }
                  },
                ),
            ],
          ),
        ),

        // ── Cart items (scrollable middle) ───────────────────────────────
        Expanded(
          child: hasItems
              ? ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: posService.cartItems.length +
                      (_showAdHocForm ? 1 : 0) +
                      1, // +1 for "add item" row
                  itemBuilder: (context, index) {
                    // Ad-hoc form at top when visible
                    if (_showAdHocForm && index == 0) {
                      return _buildAdHocFormInline(theme);
                    }
                    final itemIndex = _showAdHocForm ? index - 1 : index;
                    // "Add custom item" button
                    if (itemIndex == posService.cartItems.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 2),
                        child: GestureDetector(
                          onTap: _toggleAdHocForm,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline_rounded,
                                    size: 16,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Agregar item personalizado',
                                  style:
                                      theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    final item = posService.cartItems[itemIndex];
                    return _buildCartItemRow(theme, posService, item);
                  },
                )
              : _buildEmptyCart(theme),
        ),

        // ── Totals + payment + CTA (fixed bottom) ──────────────────────
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Totals area
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    _totalRow(
                      theme,
                      label: 'Subtotal',
                      value:
                          currencyFormat.format(posService.cartNetAmount),
                    ),
                    if (posService.cartDiscountAmount > 0) ...[
                      const SizedBox(height: 4),
                      _totalRow(
                        theme,
                        label: 'Descuento',
                        value:
                            '-${currencyFormat.format(posService.cartDiscountAmount)}',
                        valueColor: theme.colorScheme.error,
                      ),
                    ],
                    if (posService.taxTreatment ==
                        TaxTreatment.taxIncluded) ...[
                      const SizedBox(height: 4),
                      _totalRow(
                        theme,
                        label: 'IVA (19%)',
                        value: currencyFormat
                            .format(posService.cartTaxAmount),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          currencyFormat.format(posService.cartTotal),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Payment method selector
              if (hasItems) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Consumer<PaymentMethodService>(
                    builder: (context, paymentMethodService, _) {
                      final methods = paymentMethodService.paymentMethods
                          .where((m) => m.isActive)
                          .toList();
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: methods.map((method) {
                            final isSelected =
                                posService.selectedPaymentMethod?.id ==
                                    method.id;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () =>
                                    posService.setPaymentMethod(method),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? theme.colorScheme.primaryContainer
                                        : theme.colorScheme
                                            .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outlineVariant
                                              .withValues(alpha: 0.4),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _getPaymentMethodIcon(method.code),
                                        size: 15,
                                        color: isSelected
                                            ? theme.colorScheme
                                                .onPrimaryContainer
                                            : theme.colorScheme
                                                .onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        method.name,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? theme.colorScheme
                                                  .onPrimaryContainer
                                              : theme.colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ],

              // Checkout button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: hasItems ? _proceedToPayment : null,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    label: Text(
                      hasItems
                          ? 'Proceder al Pago'
                          : 'Carrito vacío',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCartItemRow(
      ThemeData theme, POSService posService, dynamic item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Quantity controls
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outlineVariant
                    .withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => posService.updateCartItemQuantity(
                      item.id, item.quantity - 1),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    child: Icon(Icons.remove_rounded,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Container(
                  width: 32,
                  height: 30,
                  alignment: Alignment.center,
                  child: Text(
                    '${item.quantity}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => posService.updateCartItemQuantity(
                      item.id, item.quantity + 1),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    child: Icon(Icons.add_rounded,
                        size: 15,
                        color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name ?? item.description ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '\$${(item.price as double).toStringAsFixed(0)} c/u',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Line total
          Text(
            '\$${((item.price as double) * (item.quantity as int)).toStringAsFixed(0)}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          // Remove
          GestureDetector(
            onTap: () => posService.removeFromCart(item.id),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdHocFormInline(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Item Personalizado',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _toggleAdHocForm,
                child: Icon(Icons.close_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _adHocDescriptionController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Descripción del item',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _adHocPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Precio',
                    prefixText: '\$',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _adHocQuantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Cant.',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _addAdHocItem,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 40),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Icon(Icons.check_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Carrito vacío',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Toca un producto para agregar',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _toggleAdHocForm,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
              label: const Text('Agregar item personalizado'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(ThemeData theme,
      {required String label, required String value, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
"""

lines = content.splitlines(keepends=True)
pre = "".join(lines[:2006])
post = "".join(lines[2446:])

new_content = pre + replacement + "\n" + post

with open('/Users/Claudio/Dev/bikeshop-erp/lib/modules/pos/pages/pos_dashboard_page.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)

print("Replacement successful")
