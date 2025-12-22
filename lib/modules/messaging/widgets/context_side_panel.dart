import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../../sales/widgets/sales_invoice_editor.dart';
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
        return _InvoicePanel(
            invoiceNumber: activeReference!.id, isExpanded: isExpanded);
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
              title: 'Job #${job.jobNumber ?? "..."}',
              subtitle: 'Mecánica',
              icon: Icons.build,
              onTap: () {
                // TODO: Navigation
              },
            ),
            const Divider(height: 32),
            _buildInfoRow('Estado', job.status.displayName, highlight: true),
            _buildInfoRow('Prioridad', job.priority.displayName),
            _buildInfoRow(
                'Mecánico', job.assignedTechnicianName ?? 'Sin asignar'),
            const SizedBox(height: 16),
            _buildInfoRow('Cliente',
                '...'), // Customer name not directly on job root sometimes, check models
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
  final bool isExpanded;

  const _InvoicePanel({required this.invoiceNumber, this.isExpanded = false});

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

        // Use the new SalesInvoiceEditor
        // If expanded, use normal mode (isCompact: false) for full table view
        return SalesInvoiceEditor(
          invoiceId: invoice.id,
          isCompact: !isExpanded,
          onSaved: () {
            // Optional: refresh parent or show toast
          },
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
    required VoidCallback onTap}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.blue[700]),
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
        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      ],
    ),
  );
}

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
