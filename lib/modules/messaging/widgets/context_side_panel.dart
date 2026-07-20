import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../utils/message_parser.dart'; // For ReferenceSegment

class ContextSidePanel extends StatelessWidget {
  final ReferenceSegment? activeReference;
  final VoidCallback onClose;
  final VoidCallback? onToggleExpand;
  final bool isExpanded;

  const ContextSidePanel({
    super.key,
    required this.activeReference,
    required this.onClose,
    this.onToggleExpand,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    if (activeReference == null) return const SizedBox.shrink();

    return Container(
      width: isExpanded ? double.infinity : 350,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey[200]!)),
        color: Colors.white,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Detalles de Referencia',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                if (onToggleExpand != null)
                  IconButton(
                    icon: Icon(isExpanded
                        ? Icons.keyboard_double_arrow_right
                        : Icons.keyboard_double_arrow_left),
                    onPressed: onToggleExpand,
                    tooltip: isExpanded ? 'Colapsar' : 'Expandir',
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                  tooltip: 'Cerrar panel',
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _buildBody(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (activeReference!.type) {
      case RefType.job:
        return _JobPanel(jobNumber: activeReference!.id);
      case RefType.invoice:
        return _InvoicePanel(invoiceNumber: activeReference!.id);
      default:
        return const Center(child: Text('Tipo de referencia desconocido'));
    }
  }
}

class _JobPanel extends StatelessWidget {
  final String jobNumber;

  const _JobPanel({required this.jobNumber});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MechanicJob>>(
      future: context.read<BikeshopService>().getJobs(searchTerm: jobNumber),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final job = snapshot.data?.firstOrNull;

        if (job == null) {
          return _buildErrorState('Job #$jobNumber no encontrado');
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeaderLink(
              context,
              title: 'Trabajo ${job.jobNumber ?? "..."}',
              subtitle: 'Resumen operativo · solo lectura',
              icon: Icons.build,
              onTap: job.id == null
                  ? null
                  : () => context
                      .read<WorkspaceManager>()
                      .openRouteInWorkspace('/taller/pegas/${job.id}'),
            ),
            const Divider(height: 32),
            _buildInfoRow('Estado', job.status.displayName, highlight: true),
            _buildInfoRow('Prioridad', job.priority.displayName),
            _buildInfoRow(
                'Mecánico', job.assignedTechnicianName ?? 'Sin asignar'),
            const SizedBox(height: 16),
            _buildSectionHeader('Finanzas'),
            _buildInfoRow('Total', '\$${job.totalCost.toStringAsFixed(0)}'),
            // Add more job details here as needed
          ],
        );
      },
    );
  }
}

class _InvoicePanel extends StatelessWidget {
  final String invoiceNumber;

  const _InvoicePanel({required this.invoiceNumber});

  Future<List<Invoice>> _fetchInvoice(BuildContext context) async {
    final service = context.read<SalesService>();
    if (service.invoices.isEmpty) {
      await service.loadInvoices();
    }
    return service.searchInvoices(invoiceNumber);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Invoice>>(
      future: _fetchInvoice(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final invoice = snapshot.data?.firstOrNull;

        if (invoice == null) {
          return _buildErrorState('Comprobante #$invoiceNumber no encontrado');
        }

        final invoiceId = invoice.id;
        final status = _invoiceStatusLabel(invoice.status);
        final colorScheme = Theme.of(context).colorScheme;

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _buildHeaderLink(
              context,
              title: 'Venta ${invoice.invoiceNumber}',
              subtitle: 'Resumen contable · solo lectura',
              icon: Icons.receipt_long_outlined,
              onTap: invoiceId == null
                  ? null
                  : () => context
                      .read<WorkspaceManager>()
                      .openRouteInWorkspace('/sales/invoices/$invoiceId'),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _invoiceStatusIcon(invoice.status),
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      status,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Documento'),
            _buildInfoRow(
              'Fecha',
              DateFormat('dd/MM/yyyy').format(invoice.date),
            ),
            _buildInfoRow(
              'Cliente',
              invoice.customerName?.trim().isNotEmpty == true
                  ? invoice.customerName!.trim()
                  : 'Sin nombre',
            ),
            _buildInfoRow('Estado', status, highlight: true),
            const SizedBox(height: 18),
            _buildSectionHeader('Importes'),
            _buildInfoRow('Total', _formatClp(invoice.total)),
            _buildInfoRow('Pagado', _formatClp(invoice.paidAmount)),
            _buildInfoRow(
              'Saldo',
              _formatClp(invoice.balance),
              highlight: invoice.balance > 0,
            ),
            if (invoice.items.isNotEmpty) ...[
              const SizedBox(height: 18),
              _buildSectionHeader('Items'),
              ...invoice.items.take(6).map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)}×',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.productName?.trim().isNotEmpty == true
                                  ? item.productName!.trim()
                                  : 'Item',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _formatClp(item.lineTotal),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (invoice.items.length > 6)
                Text(
                  '+ ${invoice.items.length - 6} items en el registro completo',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: invoiceId == null
                  ? null
                  : () => context
                      .read<WorkspaceManager>()
                      .openRouteInWorkspace('/sales/invoices/$invoiceId'),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Abrir registro de venta'),
            ),
            const SizedBox(height: 10),
            Text(
              'Este panel no edita el documento. Los cambios y correcciones se realizan en el módulo de Ventas.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        );
      },
    );
  }
}

// --- Common Helpers ---

Widget _buildErrorState(String message) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.grey),
      ),
    ),
  );
}

Widget _buildSectionHeader(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.grey[500],
        letterSpacing: 1,
      ),
    ),
  );
}

Widget _buildHeaderLink(BuildContext context,
    {required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback? onTap}) {
  final colorScheme = Theme.of(context).colorScheme;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(subtitle,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ],
          ),
        ),
        if (onTap != null)
          Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
      ],
    ),
  );
}

String _formatClp(double value) => NumberFormat.currency(
      locale: 'es_CL',
      symbol: r'$',
      decimalDigits: 0,
    ).format(value);

String _invoiceStatusLabel(InvoiceStatus status) => switch (status) {
      InvoiceStatus.draft => 'Borrador',
      InvoiceStatus.sent => 'Enviada',
      InvoiceStatus.confirmed => 'Confirmada',
      InvoiceStatus.paid => 'Pagada',
      InvoiceStatus.overdue => 'Vencida',
      InvoiceStatus.cancelled => 'Anulada',
    };

IconData _invoiceStatusIcon(InvoiceStatus status) => switch (status) {
      InvoiceStatus.paid => Icons.verified_rounded,
      InvoiceStatus.cancelled => Icons.block_rounded,
      InvoiceStatus.overdue => Icons.schedule_rounded,
      _ => Icons.receipt_long_outlined,
    };

Widget _buildInfoRow(String label, String value, {bool highlight = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600])),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              color: highlight ? Colors.blue[800] : Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );
}
