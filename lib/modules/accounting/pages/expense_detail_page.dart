import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../models/expense.dart';
import '../models/expense_line.dart';
import '../models/expense_payment.dart';
import '../services/expense_service.dart';

class ExpenseDetailPage extends StatefulWidget {
  const ExpenseDetailPage({super.key, required this.expenseId});

  final String expenseId;

  @override
  State<ExpenseDetailPage> createState() => _ExpenseDetailPageState();
}

class _ExpenseDetailPageState extends State<ExpenseDetailPage> {
  late final ExpenseService _expenseService;
  final NumberFormat _currencyFormat = ChileanUtils.currencyFormat;

  Expense? _expense;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;
  bool _hasChanges = false;
  Map<String, String> _paymentMethods = {};

  @override
  void initState() {
    super.initState();
    _expenseService = context.read<ExpenseService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExpense();
    });
  }

  Future<void> _loadExpense({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _expenseService.getExpense(widget.expenseId, forceRefresh: refresh),
        _expenseService.fetchPaymentMethods(),
      ]);

      if (mounted) {
        setState(() {
          _expense = results[0] as Expense;
          _paymentMethods = results[1] as Map<String, String>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _postExpense() async {
    if (_expense == null) return;
    setState(() => _isProcessing = true);
    try {
      await _expenseService.postExpense(_expense!.id!);
      _hasChanges = true;
      await _loadExpense(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gasto contabilizado correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo contabilizar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        return MainLayout(
          title: 'Detalle de gasto',
          onBackPressed: () => context.pop(_hasChanges),
          body: _isLoading
              ? const Center(child: BrandedLoading())
              : _error != null
                  ? _buildErrorState(context)
                  : _expense == null
                      ? _buildEmptyState(context)
                      : _buildContent(context, _expense!, isMobile),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, Expense expense, bool isMobile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // New Professional Header
          _buildProfessionalHeader(context, expense, isMobile),
          const SizedBox(height: 24),

          // Reference Block (Moved here)
          if (expense.reference != null && expense.reference!.isNotEmpty) ...[
            _buildReferenceBlock(context, expense.reference!),
            const SizedBox(height: 24),
          ],

          // Lines Section
          Text('Detalle', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          _buildLinesTable(context, expense.lines, isMobile),
          const SizedBox(height: 24),

          // Summary Footer
          _buildTotalsFooter(context, expense),
          const SizedBox(height: 32),

          // Payments & Attachments
          if (expense.payments.isNotEmpty) ...[
            Text('Pagos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _buildPaymentsList(context, expense.payments),
            const SizedBox(height: 24),
          ],

          if (expense.attachments.isNotEmpty) ...[
            Text('Adjuntos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _buildAttachmentsList(context, expense.attachments),
          ]
        ],
      ),
    );
  }

  Widget _buildProfessionalHeader(
      BuildContext context, Expense expense, bool isMobile) {
    final paymentMethodName = _buildPaymentMethodsSummary(expense);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: ID + Spacer + Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  expense.expenseNumber,
                  style: TextStyle(
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                ),
              ),
              Wrap(spacing: 8, children: [
                _StatusBadge(status: expense.paymentStatus),
                if (expense.postingStatus != ExpensePostingStatus.posted)
                  _StatusBadge(status: expense.postingStatus, isPosting: true),
              ]),
            ],
          ),
          const SizedBox(height: 16),
          // Row 2: Hero Amount
          Text(
            _currencyFormat.format(expense.totalAmount),
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2937), // Dark slate
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 20),
          // Row 3: Meta Data (Category, Payment, Date)
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildMetaItem(Icons.category_outlined,
                  expense.category?.name ?? 'Sin cat.'),
              _buildMetaItem(Icons.payment_outlined, paymentMethodName),
              _buildMetaItem(Icons.calendar_today_outlined,
                  ChileanUtils.formatDate(expense.issueDate)),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          // Row 4: Supplier (Demoted) + Actions
          Row(
            children: [
              Icon(Icons.store_outlined, size: 18, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  expense.supplierName ?? 'Proveedor sin nombre',
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                      fontSize: 14),
                ),
              ),
              // Action Buttons
              if (!isMobile) ...[
                if (expense.postingStatus != ExpensePostingStatus.posted)
                  AppButton(
                    text: 'Contabilizar',
                    icon: Icons.check,
                    onPressed: _isProcessing ? null : _postExpense,
                    type: ButtonType.primary,
                  ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () async {
                    if (expense.id == null) return;
                    final updated = await context.push<bool>(
                      '/accounting/expenses/${expense.id}/edit',
                    );
                    if (updated == true && mounted) {
                      _hasChanges = true;
                      await _loadExpense(refresh: true);
                    }
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Editar',
                ),
              ]
            ],
          ),
          // Mobile Actions (Row 5)
          if (isMobile) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      if (expense.id == null) return;
                      final updated = await context.push<bool>(
                        '/accounting/expenses/${expense.id}/edit',
                      );
                      if (updated == true && mounted) {
                        _hasChanges = true;
                        await _loadExpense(refresh: true);
                      }
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Editar'),
                  ),
                ),
                const SizedBox(width: 8),
                if (expense.postingStatus != ExpensePostingStatus.posted)
                  Expanded(
                    child: AppButton(
                      text: 'Contabilizar',
                      onPressed: _isProcessing ? null : _postExpense,
                      type: ButtonType.primary,
                    ),
                  ),
              ],
            ),
          ]
        ],
      ),
    );
  }

  String _buildPaymentMethodsSummary(Expense expense) {
    // If there are explicit payments, prefer showing the breakdown.
    if (expense.payments.isNotEmpty) {
      final totalsByMethod = <String, double>{};
      for (final p in expense.payments) {
        final methodId = p.paymentMethodId;
        if (methodId == null || methodId.isEmpty) continue;
        totalsByMethod[methodId] = (totalsByMethod[methodId] ?? 0) + p.amount;
      }

      if (totalsByMethod.isNotEmpty) {
        final parts = totalsByMethod.entries
            .map((e) {
              final name = _paymentMethods[e.key] ?? 'Método';
              return '$name ${_currencyFormat.format(e.value)}';
            })
            .toList();
        return parts.join(' · ');
      }
    }

    // Fallback to the header-level method (legacy / single method).
    final methodId = expense.paymentMethodId;
    if (methodId != null && methodId.isNotEmpty) {
      return _paymentMethods[methodId] ?? 'Método de pago';
    }
    return 'Sin medio de pago';
  }

  Widget _buildMetaItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w500,
              fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildReferenceBlock(BuildContext context, String reference) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'REFERENCIA / NOTAS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reference,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }

  // Helper method for details grid if needed by legacy, but for now mostly cleaned up.
  // Replaced by _buildContent methods.

  Widget _buildLinesTable(
      BuildContext context, List<ExpenseLine> lines, bool isMobile) {
    if (lines.isEmpty) return const Text('Sin líneas de detalle.');

    if (isMobile) {
      return Column(
        children: lines
            .map((line) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(line.accountCode,
                              style: TextStyle(
                                  color: Colors.blueGrey.shade700,
                                  fontWeight: FontWeight.bold)),
                          Text(_currencyFormat.format(line.total),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text(line.accountName,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      if (line.description != null)
                        Text(line.description!,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13)),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              '${line.quantity.toStringAsFixed(1)} x ${_currencyFormat.format(line.unitPrice)}'),
                          Text('IVA (${line.taxRate.toStringAsFixed(0)}%)'),
                        ],
                      ),
                    ],
                  ),
                ))
            .toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(3),
          2: FixedColumnWidth(80),
          3: FixedColumnWidth(100),
          4: FixedColumnWidth(100),
        },
        children: [
          TableRow(
              decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12))),
              children: const [
                Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('Cuenta',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('Descripción',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('Cant.',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('Precio',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('Total',
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ]),
          ...lines.map((line) => TableRow(children: [
                Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.accountCode,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(line.accountName)
                        ])),
                Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(line.description ?? '—')),
                Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(line.quantity.toStringAsFixed(1))),
                Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(_currencyFormat.format(line.unitPrice))),
                Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(_currencyFormat.format(line.total),
                        style: const TextStyle(fontWeight: FontWeight.bold))),
              ])),
        ],
      ),
    );
  }

  Widget _buildTotalsFooter(BuildContext context, Expense expense) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            _buildTotalRow(
                'Subtotal', _currencyFormat.format(expense.subtotal)),
            const SizedBox(height: 8),
            _buildTotalRow('IVA', _currencyFormat.format(expense.taxAmount)),
            const Divider(),
            _buildTotalRow('Total', _currencyFormat.format(expense.totalAmount),
                isBold: true),
            if (expense.amountPaid > 0) ...[
              const SizedBox(height: 8),
              _buildTotalRow(
                  'Pagado', _currencyFormat.format(expense.amountPaid),
                  color: Colors.green),
              _buildTotalRow('Saldo', _currencyFormat.format(expense.balance),
                  color: expense.balance > 0 ? Colors.orange : Colors.grey),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color)),
        Text(value,
            style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: isBold ? 18 : 14,
                color: color)),
      ],
    );
  }

  Widget _buildPaymentsList(BuildContext context, List<ExpensePayment> payments) {
    return Column(
      children: payments
          .map((p) => Card(
                child: ListTile(
                  leading: const Icon(Icons.payment),
                  title: Text(_currencyFormat.format(p.amount)),
                  subtitle: Text(
                    '${_paymentMethods[p.paymentMethodId] ?? 'Método'} · ${ChileanUtils.formatDate(p.paymentDate)}',
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildAttachmentsList(
      BuildContext context, List<dynamic> attachments) {
    return Column(
      children: attachments
          .map((a) => Card(
                child: ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(a.fileName),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error, size: 48),
          const SizedBox(height: 12),
          Text(_error ?? 'Error desconocido'),
          const SizedBox(height: 16),
          AppButton(
              text: 'Reintentar',
              icon: Icons.refresh,
              onPressed: () => _loadExpense(refresh: true)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const Center(child: Text('Gasto no encontrado'));
  }
}

class _StatusBadge extends StatelessWidget {
  final dynamic status;
  final bool isPosting;
  const _StatusBadge({required this.status, this.isPosting = false});

  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey;
    String text = '';

    if (isPosting) {
      switch (status) {
        case ExpensePostingStatus.draft:
          color = Colors.orange;
          text = 'Borrador';
          break;
        case ExpensePostingStatus.posted:
          color = Colors.green;
          text = 'Contabilizado';
          break;
        case ExpensePostingStatus.voided:
          color = Colors.red;
          text = 'Anulado';
          break;
      }
    } else {
      switch (status) {
        case ExpensePaymentStatus.pending:
          color = Colors.orange;
          text = 'Pendiente';
          break;
        case ExpensePaymentStatus.scheduled:
          color = Colors.blueGrey;
          text = 'Programado';
          break;
        case ExpensePaymentStatus.partial:
          color = Colors.purple;
          text = 'Parcial';
          break;
        case ExpensePaymentStatus.paid:
          color = Colors.green;
          text = 'Pagado';
          break;
        case ExpensePaymentStatus.voided:
          color = Colors.red;
          text = 'Anulado';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}
