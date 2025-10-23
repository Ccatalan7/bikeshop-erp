import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../models/expense.dart';
import '../models/expense_line.dart';
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
      final expense = await _expenseService.getExpense(
        widget.expenseId,
        forceRefresh: refresh,
      );
      if (mounted) {
        setState(() {
          _expense = expense;
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

  Future<void> _revertExpense() async {
    if (_expense == null) return;
    setState(() => _isProcessing = true);
    try {
  await _expenseService.revertExpenseToDraft(_expense!.id!);
  _hasChanges = true;
  await _loadExpense(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gasto movido a borrador')), 
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo revertir: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _markPaid() async {
    if (_expense == null) return;
    setState(() => _isProcessing = true);
    try {
  await _expenseService.markExpensePaid(_expense!.id!);
  _hasChanges = true;
  await _loadExpense(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gasto marcado como pagado')), 
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo marcar como pagado: $e')),
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
    return MainLayout(
      title: 'Detalle de gasto',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(context)
              : _expense == null
                  ? _buildEmptyState(context)
                  : _buildContent(context),
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
          Text(
            'No se pudo cargar el gasto',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(_error ?? 'Error desconocido'),
          const SizedBox(height: 16),
          AppButton(
            text: 'Reintentar',
            icon: Icons.refresh,
            onPressed: () => _loadExpense(refresh: true),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long,
              size: 48, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text('No encontramos este gasto'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.pop(_hasChanges),
            child: const Text('Volver'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final expense = _expense!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderRow(context, expense),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCard(context, expense),
                  const SizedBox(height: 16),
                  _buildStatusChips(context, expense),
                  const SizedBox(height: 24),
                  _buildInfoCards(context, expense),
                  const SizedBox(height: 24),
                  _buildLinesSection(context, expense.lines),
                  const SizedBox(height: 24),
                  _buildPaymentsSection(context, expense),
                  const SizedBox(height: 24),
                  _buildAttachmentsSection(context, expense),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context, Expense expense) {
    return Row(
      children: [
        IconButton(
          onPressed: () => context.pop(_hasChanges),
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(
            'Gasto ${expense.expenseNumber}',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        if (!_isLoading) ...[
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => _loadExpense(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          AppButton(
            text: 'Editar',
            icon: Icons.edit_outlined,
            type: ButtonType.secondary,
            onPressed: () async {
              if (expense.id == null) return;
              final updated = await context.push<bool>(
                '/accounting/expenses/${expense.id}/edit',
              );
              if (updated == true && mounted) {
                _hasChanges = true;
                await _loadExpense(refresh: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Gasto actualizado correctamente'),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            enabled: !_isProcessing,
            onSelected: (value) {
              switch (value) {
                case 'post':
                  _postExpense();
                  break;
                case 'draft':
                  _revertExpense();
                  break;
                case 'paid':
                  _markPaid();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'post',
                enabled: expense.postingStatus != ExpensePostingStatus.posted,
                child: const ListTile(
                  leading: Icon(Icons.task_alt_outlined),
                  title: Text('Marcar como contabilizado'),
                ),
              ),
              PopupMenuItem(
                value: 'draft',
                enabled: expense.postingStatus == ExpensePostingStatus.posted,
                child: const ListTile(
                  leading: Icon(Icons.undo_outlined),
                  title: Text('Volver a borrador'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'paid',
                enabled: expense.paymentStatus != ExpensePaymentStatus.paid,
                child: const ListTile(
                  leading: Icon(Icons.payments_outlined),
                  title: Text('Marcar como pagado'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(BuildContext context, Expense expense) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currencyFormat.format(expense.totalAmount),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Subtotal: ${_currencyFormat.format(expense.subtotal)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    'IVA: ${_currencyFormat.format(expense.taxAmount)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (expense.amountPaid > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Pagado: ${_currencyFormat.format(expense.amountPaid)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.green.shade700),
                    ),
                    Text(
                      'Saldo pendiente: ${_currencyFormat.format(expense.balance)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.orange.shade700),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Emitido: ${ChileanUtils.formatDate(expense.issueDate)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (expense.dueDate != null)
                  Text(
                    'Vence: ${ChileanUtils.formatDate(expense.dueDate!)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                if (expense.category?.name != null) ...[
                  const SizedBox(height: 12),
                  Chip(
                    avatar: const Icon(Icons.label_outline, size: 16),
                    label: Text(expense.category!.name),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChips(BuildContext context, Expense expense) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _statusChip(
          context,
          label: _postingStatusLabel(expense.postingStatus),
          color: _postingStatusColor(expense.postingStatus),
          icon: Icons.account_balance_outlined,
        ),
        _statusChip(
          context,
          label: _paymentStatusLabel(expense.paymentStatus),
          color: _paymentStatusColor(expense.paymentStatus),
          icon: Icons.payments_outlined,
        ),
        _statusChip(
          context,
          label: _documentTypeLabel(expense.documentType),
          color: Theme.of(context).colorScheme.secondaryContainer,
          icon: Icons.description_outlined,
        ),
        if (expense.approvalStatus != ExpenseApprovalStatus.pending)
          _statusChip(
            context,
            label: _approvalStatusLabel(expense.approvalStatus),
            color: expense.approvalStatus == ExpenseApprovalStatus.approved
                ? Colors.green.shade100
                : Colors.red.shade100,
            icon: Icons.verified_user_outlined,
          ),
      ],
    );
  }

  Widget _statusChip(
    BuildContext context, {
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Chip(
      avatar: Icon(icon, size: 18, color: Colors.black87),
      label: Text(label),
      backgroundColor: color,
    );
  }

  Widget _buildInfoCards(BuildContext context, Expense expense) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _infoCard(
          context,
          title: 'Proveedor',
          content: expense.supplierName ?? 'Sin proveedor',
          subtitle: expense.supplierRut,
          icon: Icons.store_outlined,
        ),
        _infoCard(
          context,
          title: 'Referencia',
          content: expense.reference ?? 'Sin referencia',
          subtitle: expense.paymentTerms,
          icon: Icons.notes_outlined,
        ),
        _infoCard(
          context,
          title: 'Cuentas contables',
          content: expense.liabilityAccountId ?? 'Cuenta por pagar',
          subtitle: expense.paymentAccountId,
          icon: Icons.account_tree_outlined,
        ),
        _infoCard(
          context,
          title: 'Creado por',
          content: expense.createdBy ?? 'No registrado',
          subtitle: expense.createdAt != null
              ? ChileanUtils.formatDateTime(expense.createdAt!)
              : null,
          icon: Icons.person_outline,
        ),
      ],
    );
  }

  Widget _infoCard(
    BuildContext context, {
    required String title,
    required String content,
    String? subtitle,
    required IconData icon,
  }) {
    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                content,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinesSection(BuildContext context, List<ExpenseLine> lines) {
    if (lines.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Detalle contable'),
              SizedBox(height: 8),
              Text('Este gasto no tiene líneas asociadas.'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle contable',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Cuenta')),
                  DataColumn(label: Text('Descripción')),
                  DataColumn(label: Text('Cantidad')),
                  DataColumn(label: Text('Precio unitario')),
                  DataColumn(label: Text('Subtotal')),
                  DataColumn(label: Text('IVA')),
                  DataColumn(label: Text('Total')),
                ],
                rows: [
                  for (var i = 0; i < lines.length; i++)
                    DataRow(
                      cells: [
                        DataCell(Text((i + 1).toString())),
                        DataCell(Text(
                            '${lines[i].accountCode} · ${lines[i].accountName}')),
                        DataCell(Text(lines[i].description ?? '—')),
                        DataCell(Text(lines[i].quantity.toStringAsFixed(2))),
                        DataCell(Text(_currencyFormat.format(lines[i].unitPrice))),
                        DataCell(Text(_currencyFormat.format(lines[i].subtotal))),
                        DataCell(Text(
                            '${lines[i].taxRate.toStringAsFixed(0)}% (${_currencyFormat.format(lines[i].taxAmount)})')),
                        DataCell(Text(_currencyFormat.format(lines[i].total))),
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

  Widget _buildPaymentsSection(BuildContext context, Expense expense) {
    if (expense.payments.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Pagos'),
              SizedBox(height: 8),
              Text('Este gasto aún no registra pagos.'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pagos',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...expense.payments.map(
              (payment) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.payments_outlined),
                title: Text(_currencyFormat.format(payment.amount)),
                subtitle: Text(
                  'Fecha: ${ChileanUtils.formatDate(payment.paymentDate)}'
                  '${payment.reference != null ? ' · Ref: ${payment.reference}' : ''}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection(BuildContext context, Expense expense) {
    if (expense.attachments.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Adjuntos'),
              SizedBox(height: 8),
              Text('No hay documentos adjuntos en este gasto.'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adjuntos',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...expense.attachments.map(
              (attachment) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file_outlined),
                title: Text(attachment.fileName),
                subtitle: Text(
                  attachment.uploadedAt != null
                      ? 'Subido el ${ChileanUtils.formatDateTime(attachment.uploadedAt!)}'
                      : 'Sin fecha registrada',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _postingStatusLabel(ExpensePostingStatus status) {
    switch (status) {
      case ExpensePostingStatus.draft:
        return 'Borrador';
      case ExpensePostingStatus.posted:
        return 'Contabilizado';
      case ExpensePostingStatus.voided:
        return 'Anulado';
    }
  }

  Color _postingStatusColor(ExpensePostingStatus status) {
    switch (status) {
      case ExpensePostingStatus.draft:
        return Colors.orange.shade100;
      case ExpensePostingStatus.posted:
        return Colors.green.shade100;
      case ExpensePostingStatus.voided:
        return Colors.red.shade100;
    }
  }

  String _paymentStatusLabel(ExpensePaymentStatus status) {
    switch (status) {
      case ExpensePaymentStatus.pending:
        return 'Pendiente';
      case ExpensePaymentStatus.scheduled:
        return 'Programado';
      case ExpensePaymentStatus.partial:
        return 'Parcial';
      case ExpensePaymentStatus.paid:
        return 'Pagado';
      case ExpensePaymentStatus.voided:
        return 'Anulado';
    }
  }

  Color _paymentStatusColor(ExpensePaymentStatus status) {
    switch (status) {
      case ExpensePaymentStatus.pending:
        return Colors.orange.shade100;
      case ExpensePaymentStatus.scheduled:
        return Colors.blueGrey.shade100;
      case ExpensePaymentStatus.partial:
        return Colors.deepPurple.shade100;
      case ExpensePaymentStatus.paid:
        return Colors.green.shade100;
      case ExpensePaymentStatus.voided:
        return Colors.red.shade100;
    }
  }

  String _documentTypeLabel(ExpenseDocumentType type) {
    switch (type) {
      case ExpenseDocumentType.invoice:
        return 'Factura';
      case ExpenseDocumentType.receipt:
        return 'Boleta';
      case ExpenseDocumentType.ticket:
        return 'Ticket';
      case ExpenseDocumentType.reimbursement:
        return 'Reembolso';
      case ExpenseDocumentType.other:
        return 'Otro';
    }
  }

  String _approvalStatusLabel(ExpenseApprovalStatus status) {
    switch (status) {
      case ExpenseApprovalStatus.pending:
        return 'Pendiente';
      case ExpenseApprovalStatus.approved:
        return 'Aprobado';
      case ExpenseApprovalStatus.rejected:
        return 'Rechazado';
    }
  }
}
