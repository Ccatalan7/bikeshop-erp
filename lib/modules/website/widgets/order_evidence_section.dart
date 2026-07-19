import 'package:flutter/material.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../models/online_order_official_document.dart';
import '../models/order_communication.dart';
import '../services/order_evidence_service.dart';

typedef OpenOfficialOrderDocument = void Function(
  OnlineOrderOfficialDocument document,
  Uri verifiedUri,
);

/// Read-only evidence surface for the canonical online-order inspector.
///
/// This widget never sends, retries or mutates communications/documents. Its
/// only actions are reloading the read model and opening already-verified
/// evidence through callbacks owned by the host.
class OrderEvidenceSection extends StatefulWidget {
  const OrderEvidenceSection({
    super.key,
    required this.orderId,
    required this.salesInvoiceId,
    required this.onOpenOfficialDocument,
    this.service,
  });

  final String orderId;
  final String? salesInvoiceId;
  final OpenOfficialOrderDocument onOpenOfficialDocument;
  final OrderEvidenceReader? service;

  @override
  State<OrderEvidenceSection> createState() => _OrderEvidenceSectionState();
}

class _OrderEvidenceSectionState extends State<OrderEvidenceSection> {
  late OrderEvidenceReader _service;
  late Future<OnlineOrderEvidence> _evidenceFuture;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? OrderEvidenceService();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrderEvidenceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId ||
        oldWidget.service != widget.service) {
      _service = widget.service ?? OrderEvidenceService();
      _load();
    }
  }

  void _load() {
    _evidenceFuture = _service.loadForOrder(widget.orderId);
  }

  void _reload() {
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnlineOrderEvidence>(
      future: _evidenceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _EvidenceLoading();
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _EvidenceLoadError(onRetry: _reload);
        }
        return _EvidenceBody(
          evidence: snapshot.data!,
          salesInvoiceId: widget.salesInvoiceId,
          onOpenOfficialDocument: widget.onOpenOfficialDocument,
        );
      },
    );
  }
}

class _EvidenceBody extends StatelessWidget {
  const _EvidenceBody({
    required this.evidence,
    required this.salesInvoiceId,
    required this.onOpenOfficialDocument,
  });

  final OnlineOrderEvidence evidence;
  final String? salesInvoiceId;
  final OpenOfficialOrderDocument onOpenOfficialDocument;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasInternalSale = salesInvoiceId?.trim().isNotEmpty == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EvidenceHeading(
          title: 'Documentos',
          count: evidence.officialDocuments.length + (hasInternalSale ? 1 : 0),
        ),
        const SizedBox(height: 4),
        if (evidence.officialDocuments.isEmpty)
          const _EmptyEvidenceRow(
            icon: Icons.verified_outlined,
            title: 'Sin documento oficial registrado',
            detail:
                'El pago o la venta ERP no se presentan como boleta sin evidencia fiscal verificable.',
          )
        else
          for (var index = 0;
              index < evidence.officialDocuments.length;
              index++) ...[
            _OfficialDocumentRow(
              document: evidence.officialDocuments[index],
              onOpen: onOpenOfficialDocument,
            ),
            if (index < evidence.officialDocuments.length - 1)
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ],
        if (hasInternalSale) ...[
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const _InternalSaleRow(),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'La venta ERP y el comprobante de confirmación son respaldos internos no tributarios; no sustituyen una boleta.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _EvidenceHeading(
          title: 'Comunicaciones al cliente',
          count: evidence.communications.length,
        ),
        const SizedBox(height: 4),
        if (evidence.communications.isEmpty)
          const _EmptyEvidenceRow(
            icon: Icons.mail_outline_rounded,
            title: 'Sin comunicaciones registradas',
            detail: 'Todavía no existe evidencia de envío para este pedido.',
          )
        else
          for (var index = 0;
              index < evidence.communications.length;
              index++) ...[
            _CommunicationRow(communication: evidence.communications[index]),
            if (index < evidence.communications.length - 1)
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ],
      ],
    );
  }
}

class _EvidenceHeading extends StatelessWidget {
  const _EvidenceHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          '$count ${count == 1 ? 'registro' : 'registros'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _OfficialDocumentRow extends StatelessWidget {
  const _OfficialDocumentRow({
    required this.document,
    required this.onOpen,
  });

  final OnlineOrderOfficialDocument document;
  final OpenOfficialOrderDocument onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verifiedUri = document.verifiedArtifactUri;
    final reference = document.referenceLabel;
    final date = ChileanUtils.formatDateTime(document.issuedAt.toLocal());
    final amount = ChileanUtils.formatCurrency(document.amount);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                document.displayLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$reference · $date · $amount',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final action = verifiedUri == null
              ? const _PlainState(
                  icon: Icons.link_off_rounded,
                  label: 'Enlace no verificable',
                  color: Color(0xFF8B6927),
                )
              : TextButton.icon(
                  onPressed: () => onOpen(document, verifiedUri),
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('Abrir documento'),
                );

          if (compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EvidenceIcon(
                  icon: document.isMercadoPagoVoucherValidAsBoleta
                      ? Icons.payments_outlined
                      : Icons.receipt_long_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      details,
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerLeft, child: action),
                    ],
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              _EvidenceIcon(
                icon: document.isMercadoPagoVoucherValidAsBoleta
                    ? Icons.payments_outlined
                    : Icons.receipt_long_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(child: details),
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _InternalSaleRow extends StatelessWidget {
  const _InternalSaleRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const _EvidenceIcon(icon: Icons.description_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Venta ERP vinculada',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Respaldo interno · no tributario',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunicationRow extends StatelessWidget {
  const _CommunicationRow({required this.communication});

  final OrderCommunication communication;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _CommunicationState.from(communication);
    final date = ChileanUtils.formatDateTime(
      _communicationTimestamp(communication).toLocal(),
    );
    final attemptSuffix = communication.attemptCount > 1
        ? ' · ${communication.attemptCount} intentos'
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                communication.messageLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                communication.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(
                '${communication.recipientEmail}$attemptSuffix',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final status = Column(
            crossAxisAlignment:
                compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              _PlainState(
                icon: state.icon,
                label: state.label,
                color: state.color,
              ),
              const SizedBox(height: 3),
              Text(
                date,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );

          if (compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _EvidenceIcon(icon: Icons.mail_outline_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      details,
                      const SizedBox(height: 7),
                      status,
                    ],
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _EvidenceIcon(icon: Icons.mail_outline_rounded),
              const SizedBox(width: 12),
              Expanded(child: details),
              const SizedBox(width: 16),
              SizedBox(width: 150, child: status),
            ],
          );
        },
      ),
    );
  }
}

class _EvidenceIcon extends StatelessWidget {
  const _EvidenceIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 28,
      height: 28,
      child: Icon(
        icon,
        size: 19,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _PlainState extends StatelessWidget {
  const _PlainState({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _EmptyEvidenceRow extends StatelessWidget {
  const _EmptyEvidenceRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EvidenceIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceLoading extends StatelessWidget {
  const _EvidenceLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(child: Text('Cargando trazabilidad...')),
        ],
      ),
    );
  }
}

class _EvidenceLoadError extends StatelessWidget {
  const _EvidenceLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.error,
            size: 19,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('No se pudo cargar la trazabilidad del pedido.'),
          ),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

DateTime _communicationTimestamp(OrderCommunication communication) {
  return communication.deliveredAt ??
      communication.bouncedAt ??
      communication.complainedAt ??
      communication.failedAt ??
      communication.submittedAt ??
      communication.renderedAt ??
      communication.createdAt;
}

class _CommunicationState {
  const _CommunicationState(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  factory _CommunicationState.from(OrderCommunication communication) {
    if (communication.isDryRun) {
      return const _CommunicationState(
        'Simulación · no enviado',
        Icons.science_outlined,
        Color(0xFF686F78),
      );
    }
    return switch (communication.state) {
      'delivered' => const _CommunicationState(
          'Entregado',
          Icons.check_circle_outline_rounded,
          Color(0xFF4F755A),
        ),
      'submitted' => const _CommunicationState(
          'Enviado',
          Icons.send_outlined,
          Color(0xFF4B7087),
        ),
      'delivery_delayed' => const _CommunicationState(
          'Entrega demorada',
          Icons.schedule_rounded,
          Color(0xFF8B6927),
        ),
      'bounced' => const _CommunicationState(
          'Rebotado',
          Icons.reply_all_rounded,
          Color(0xFF985858),
        ),
      'complained' => const _CommunicationState(
          'Reportado',
          Icons.report_outlined,
          Color(0xFF985858),
        ),
      'failed' => const _CommunicationState(
          'Falló',
          Icons.error_outline_rounded,
          Color(0xFF985858),
        ),
      'dead_letter' => const _CommunicationState(
          'Intentos agotados',
          Icons.error_outline_rounded,
          Color(0xFF985858),
        ),
      'suppressed' => const _CommunicationState(
          'Suprimido',
          Icons.block_rounded,
          Color(0xFF8B6927),
        ),
      'leased' => const _CommunicationState(
          'Procesando',
          Icons.sync_rounded,
          Color(0xFF686F78),
        ),
      'rendered' => const _CommunicationState(
          'Preparado',
          Icons.description_outlined,
          Color(0xFF686F78),
        ),
      _ => const _CommunicationState(
          'Pendiente',
          Icons.schedule_rounded,
          Color(0xFF686F78),
        ),
    };
  }
}
