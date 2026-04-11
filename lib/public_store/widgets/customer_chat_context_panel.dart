import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../modules/bikeshop/models/bikeshop_models.dart';
import '../../modules/bikeshop/services/bikeshop_service.dart';
import '../../modules/sales/models/sales_models.dart';
import '../../modules/sales/services/sales_service.dart';

class CustomerChatContextPanel extends StatelessWidget {
  final String contextType;
  final String contextId;

  const CustomerChatContextPanel({
    super.key,
    required this.contextType,
    required this.contextId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildBody(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    String title = 'Detalles';
    IconData icon = Icons.info_outline;

    switch (contextType) {
      case 'job':
        title = 'Servicio Técnico';
        icon = Icons.build_circle_outlined;
        break;
      case 'invoice':
        title = 'Presupuesto / Factura';
        icon = Icons.receipt_long;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (contextType) {
      case 'job':
        return _JobDetails(jobId: contextId);
      case 'invoice':
        return _InvoiceDetails(invoiceId: contextId);
      default:
        return Center(
          child: Text('Contexto no soportado: $contextType'),
        );
    }
  }
}

class _JobDetails extends StatelessWidget {
  final String jobId;

  const _JobDetails({required this.jobId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MechanicJob?>(
      future: context.read<BikeshopService>().getJobById(jobId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator()));
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(
              child: Text('No se encontró la información del servicio.'));
        }

        final job = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(
              job.status.displayName,
              _getStatusColor(job.status),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Información'),
            _buildInfoRow('N° Orden', '#${job.jobNumber ?? "---"}'),
            if (job.bikeId != null)
              FutureBuilder<Bike?>(
                future:
                    context.read<BikeshopService>().getBikeById(job.bikeId!),
                builder: (context, bikeSnap) {
                  if (!bikeSnap.hasData) return const SizedBox.shrink();
                  final bike = bikeSnap.data!;
                  return _buildInfoRow(
                      'Bicicleta', '${bike.brand ?? ""} ${bike.model ?? ""}');
                },
              )
            else
              _buildInfoRow(
                'Elemento',
                job.subjectData?.name ?? job.jobType.displayName,
              ),
            _buildInfoRow(
                'Ingreso', DateFormat('dd/MM/yyyy').format(job.arrivalDate)),
            _buildInfoRow(
                'Mecánico', job.assignedTechnicianName ?? 'Por asignar'),
            const SizedBox(height: 24),
            _buildSectionTitle('Diagnóstico / Nota'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Text(
                job.clientRequest?.isNotEmpty == true
                    ? job.clientRequest!
                    : 'Sin notas adicionales.',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ),
            if (job.invoiceId != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              _buildSectionTitle('Presupuesto'),
              _InvoiceMiniSummary(invoiceId: job.invoiceId!),
            ],
          ],
        );
      },
    );
  }

  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.enCurso:
      case JobStatus.diagnostico:
        return Colors.blue;
      case JobStatus.esperandoAprobacion:
      case JobStatus.esperandoRepuestos:
        return Colors.orange;
      case JobStatus.finalizado:
        return Colors.green;
      case JobStatus.entregado:
        return Colors.grey;
      case JobStatus.cancelado:
      case JobStatus.pendiente:
        return Colors.black;
    }
  }
}

class _InvoiceDetails extends StatelessWidget {
  final String invoiceId;

  const _InvoiceDetails({required this.invoiceId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Invoice?>(
      future: context.read<SalesService>().fetchInvoice(invoiceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator()));
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(child: Text('No se encontró el presupuesto.'));
        }

        final invoice = snapshot.data!;
        final statusColor = invoice.status == InvoiceStatus.confirmed
            ? Colors.green
            : (invoice.status == InvoiceStatus.paid
                ? Colors.purple
                : Colors.orange);

        final statusLabel = invoice.status == InvoiceStatus.confirmed
            ? 'CONFIRMADO'
            : (invoice.status == InvoiceStatus.paid
                ? 'PAGADO'
                : 'BORRADOR / ENVIADO');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(statusLabel, statusColor),
            const SizedBox(height: 24),
            _buildSectionTitle('Items'),
            ...invoice.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${item.quantity}x',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName ?? 'Item',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            Text('\$${item.unitPrice.toStringAsFixed(0)}',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      ),
                      Text('\$${item.lineTotal.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                )),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontSize: 16)),
                Text('\$${invoice.total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            if (invoice.status == InvoiceStatus.sent) ...[
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    // TODO: Trigger confirm action via Notification or Chat Action
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Por favor confirma en el chat.')));
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('CONFIRMAR PRESUPUESTO'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ]
          ],
        );
      },
    );
  }
}

class _InvoiceMiniSummary extends StatelessWidget {
  final String invoiceId;
  const _InvoiceMiniSummary({required this.invoiceId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Invoice?>(
      future: context.read<SalesService>().fetchInvoice(invoiceId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final invoice = snapshot.data!;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[100]!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Presupuestado',
                      style: TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  Text('\$${invoice.total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              if (invoice.status == InvoiceStatus.sent)
                Icon(Icons.pending, color: Colors.blue[300]),
              if (invoice.status == InvoiceStatus.confirmed)
                const Icon(Icons.check_circle, color: Colors.green),
            ],
          ),
        );
      },
    );
  }
}

// Helpers

Widget _buildSectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.grey[500],
        letterSpacing: 1,
      ),
    ),
  );
}

Widget _buildInfoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

Widget _buildStatusCard(String label, Color color) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        Icon(Icons.info, color: color, size: 20),
        const SizedBox(width: 12),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}
