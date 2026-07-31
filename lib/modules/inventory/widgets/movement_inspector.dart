import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../purchases/models/purchase_invoice.dart';
import '../../sales/models/sales_models.dart';
import '../models/stock_adjustment.dart';
import '../models/stock_movement.dart';
import '../services/stock_movements_service.dart';

/// The right-hand inspector for one ledger row.
///
/// It answers the three questions an operator asks of a movement, in the order
/// they ask them: *what happened* (the movement itself), *can I trust it* (the
/// evidence, in words), and *what justifies it* (the document). The old
/// surface answered them backwards — it took over the whole pane to re-render
/// the entire invoice, pushed the audit explanation into a dense band above
/// it, and made returning to the ledger a full reload.
///
/// The full document deliberately does not render here. Re-painting an invoice
/// inside inventory duplicated the sales module's renderer line for line, and
/// the two drifted. The inspector shows the document's identity, its state and
/// the one line that touched this product, then routes to the module that owns
/// it — the return contract restores this exact ledger, filters and scroll.
class MovementInspector extends StatelessWidget {
  const MovementInspector({
    required this.movement,
    required this.onClose,
    this.storeTimezone = stockMovementsDefaultStoreTimezone,
    this.salesInvoice,
    this.purchaseInvoice,
    this.adjustment,
    this.loadingDocument = false,
    this.documentError,
    this.onRetryDocument,
    this.onOpenDocument,
    this.operationTrace,
    this.loadingOperationTrace = false,
    this.operationTraceError,
    this.onRetryOperationTrace,
    super.key,
  });

  final StockMovement movement;
  final VoidCallback onClose;
  final String storeTimezone;
  final Invoice? salesInvoice;
  final PurchaseInvoice? purchaseInvoice;
  final StockAdjustmentDetail? adjustment;
  final bool loadingDocument;
  final String? documentError;
  final VoidCallback? onRetryDocument;
  final VoidCallback? onOpenDocument;
  final Map<String, dynamic>? operationTrace;
  final bool loadingOperationTrace;
  final String? operationTraceError;
  final VoidCallback? onRetryOperationTrace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InspectorHeader(movement: movement, onClose: onClose),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _MovementSection(
                  movement: movement,
                  storeTimezone: storeTimezone,
                ),
                const SizedBox(height: 14),
                _EvidenceSection(
                  movement: movement,
                  operationTrace: operationTrace,
                  loadingOperationTrace: loadingOperationTrace,
                  operationTraceError: operationTraceError,
                  onRetryOperationTrace: onRetryOperationTrace,
                ),
                const SizedBox(height: 14),
                _DocumentSection(
                  movement: movement,
                  salesInvoice: salesInvoice,
                  purchaseInvoice: purchaseInvoice,
                  adjustment: adjustment,
                  loading: loadingDocument,
                  error: documentError,
                  onRetry: onRetryDocument,
                  onOpen: onOpenDocument,
                  storeTimezone: storeTimezone,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({required this.movement, required this.onClose});

  final StockMovement movement;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final type = movement.movementTypeDisplay.trim();
    final origin = movement.sourceDisplay.trim();
    // "Recepción · Recepción de compra" says the first word twice; when one
    // side already contains the other, the longer one carries both meanings.
    final lowerType = type.toLowerCase();
    final lowerOrigin = origin.toLowerCase();
    final subtitle =
        lowerOrigin.contains(lowerType) || lowerType.contains(lowerOrigin)
            ? (origin.length >= type.length ? origin : type)
            : '$type · $origin';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.referenceDisplay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Cerrar detalle',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}

/// One quiet titled block. Grouping comes from the title and a hairline, not
/// from a card per fact.
class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MovementSection extends StatelessWidget {
  const _MovementSection({
    required this.movement,
    required this.storeTimezone,
  });

  final StockMovement movement;
  final String storeTimezone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final change = movement.summaryQuantity;
    final registered = DateFormat('dd/MM/yyyy HH:mm').format(
      stockMovementStoreTime(
        movement.createdAt,
        storeTimezone: storeTimezone,
      ),
    );
    final effective = DateFormat('dd/MM/yyyy HH:mm').format(
      stockMovementStoreTime(
        movement.transactionDate,
        storeTimezone: storeTimezone,
      ),
    );
    // The business date only earns a row when it disagrees with the ledger
    // instant; printing two identical timestamps is noise.
    final datesDiffer =
        movement.createdAt.difference(movement.transactionDate).abs() >
            const Duration(minutes: 1);

    return _InspectorPanel(
      title: 'Movimiento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Cambio',
                  child: Text(
                    change >= 0 ? '+$change' : '$change',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: change >= 0 ? colors.tertiary : colors.error,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 34, color: colors.outlineVariant),
              const SizedBox(width: 14),
              Expanded(
                child: _Figure(
                  label: 'Saldo',
                  child: Text.rich(
                    TextSpan(
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      children: [
                        TextSpan(
                          text: '${movement.stockBefore}',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        TextSpan(
                          text: ' → ',
                          style: TextStyle(color: colors.outline),
                        ),
                        TextSpan(text: '${movement.stockAfter}'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DefinitionRow(label: 'Producto', value: movement.productName),
          _DefinitionRow(label: 'Registrado', value: registered),
          if (datesDiffer)
            _DefinitionRow(label: 'Fecha efectiva', value: effective),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _DefinitionRow extends StatelessWidget {
  const _DefinitionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The audit story, told as a sentence first and as fields only on request.
///
/// The previous surface printed the whole explanation, the two dates and an
/// orange all-caps trigger warning above every document. The evidence is
/// context, not an alarm: one plain sentence carries the verdict, and the
/// trigger/provenance detail waits behind a labelled disclosure.
class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({
    required this.movement,
    required this.operationTrace,
    required this.loadingOperationTrace,
    required this.operationTraceError,
    required this.onRetryOperationTrace,
  });

  final StockMovement movement;
  final Map<String, dynamic>? operationTrace;
  final bool loadingOperationTrace;
  final String? operationTraceError;
  final VoidCallback? onRetryOperationTrace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final verdict = _verdict(movement);
    final verified = movement.integrityStatus == 'verified' ||
        movement.integrityStatus == 'verified_adjustment';

    return _InspectorPanel(
      title: 'Evidencia',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                verified ? Icons.verified_outlined : Icons.info_outline,
                size: 16,
                color: verified ? colors.onSurfaceVariant : colors.tertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  verdict,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          if (loadingOperationTrace) ...[
            const SizedBox(height: 10),
            const _TraceLoadingState(),
          ] else if (operationTraceError != null) ...[
            const SizedBox(height: 10),
            _TraceErrorState(
              message: operationTraceError!,
              onRetry: onRetryOperationTrace,
            ),
          ],
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 2),
              dense: true,
              title: Text(
                'Detalle técnico',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                _DefinitionRow(
                  label: 'Libro',
                  value: _ledgerBalanceLabel(movement.balanceProvenance),
                ),
                _DefinitionRow(
                  label: 'Saldo de origen',
                  value: movement.hasRecordedSourceBalance
                      ? '${movement.evidenceStockBefore} → '
                          '${movement.evidenceStockAfter} · '
                          '${_sourceBalanceLabel(movement.evidenceBalanceProvenance)}'
                      : 'Saldo de origen no registrado; los valores del libro '
                          'son una reconstrucción y no evidencia de la fuente.',
                ),
                _DefinitionRow(
                  label: 'Estado',
                  value: '${movement.integrityLabel} '
                      '(${movement.integrityStatus})',
                ),
                if (movement.hasRawActualDifference)
                  _DefinitionRow(
                    label: 'Huella original',
                    value: '${_signed(movement.rawQuantity)} registrado · '
                        '${_signed(movement.actualStockDelta)} cambio real',
                  ),
                if (movement.isSummaryExcluded)
                  const _DefinitionRow(
                    label: 'Totales',
                    value: 'Excluido para evitar doble conteo.',
                  ),
                const SizedBox(height: 6),
                _OperationTraceDetails(
                  movement: movement,
                  trace: operationTrace,
                  loading: loadingOperationTrace,
                  error: operationTraceError,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _verdict(StockMovement movement) {
    switch (movement.integrityStatus) {
      case 'verified':
        return 'La aritmética de los saldos registrados por el movimiento es '
            'consistente. El documento y la operación se informan por separado.';
      case 'verified_adjustment':
        return 'El ajuste enlazado conserva saldos propios y una aritmética '
            'consistente.';
      case 'legacy_reconstructed':
        return 'Movimiento anterior al sistema de trazabilidad. La versión '
            'antigua no guardaba saldos propios, por lo que fueron '
            'encadenados desde el stock actual.';
      case 'legacy_duplicate_footprint':
        return 'Huella duplicada: existe un ajuste espejo del mismo instante. '
            'Esta fila se excluye de los totales para no contar dos veces.';
      case 'legacy_purchase_reversal_collision':
        return 'Colisión de reversión histórica: la compra y su reversión '
            'comparten instante. El delta mostrado es el probado.';
      case 'ledger_source_balance_mismatch':
        return 'El saldo del documento de origen no encadena con el libro. '
            'Requiere revisión; la causa no se atribuye automáticamente.';
      case 'arithmetic_mismatch':
        return 'Error aritmético: saldo inicial + cambio no coincide con el '
            'saldo final registrado.';
      case 'legacy_ambiguous_adjustment_match':
        return 'Vínculo histórico ambiguo: más de un ajuste coincide con la '
            'huella y el sistema no inventó una asociación.';
      default:
        return 'Estado de integridad no reconocido. Este movimiento no se '
            'presenta como verificado.';
    }
  }

  static String _ledgerBalanceLabel(String provenance) {
    return switch (provenance) {
      'persisted_movement' => 'Registrado por el movimiento',
      'current_stock_reconciled_ledger' =>
        'Reconstruido y encadenado desde el stock actual',
      _ => 'Reconstruido desde el stock actual',
    };
  }

  static String _sourceBalanceLabel(String provenance) {
    return switch (provenance) {
      'stock_adjustment' => 'registrado por el ajuste',
      'legacy_collision_adjustment' =>
        'registrado por el ajuste histórico enlazado',
      _ => provenance,
    };
  }

  static String _signed(int value) => value >= 0 ? '+$value' : '$value';
}

class _TraceLoadingState extends StatelessWidget {
  const _TraceLoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Cargando traza de la operación…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _TraceErrorState extends StatelessWidget {
  const _TraceErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.zero,
            ),
            child: const Text('Reintentar traza'),
          ),
      ],
    );
  }
}

class _OperationTraceDetails extends StatelessWidget {
  const _OperationTraceDetails({
    required this.movement,
    required this.trace,
    required this.loading,
    required this.error,
  });

  final StockMovement movement;
  final Map<String, dynamic>? trace;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final operationId = movement.operationId;
    if (operationId == null || operationId.isEmpty) {
      return const _DefinitionRow(
        label: 'Operación',
        value: 'Anterior al sistema de trazabilidad.',
      );
    }
    if (loading) {
      return const _DefinitionRow(
        label: 'Operación',
        value: 'Cargando detalle…',
      );
    }
    if (error != null || trace == null) {
      return _DefinitionRow(
        label: 'Operación',
        value: '$operationId · detalle no disponible',
      );
    }

    final parentOperationId = _text(trace!['parent_operation_id']);
    final parentAction = _text(trace!['parent_action']);
    final action =
        parentAction ?? _text(trace!['action']) ?? movement.triggerAction;
    final actor = _text(trace!['parent_actor_id']) ??
        _text(trace!['actor_id']) ??
        movement.triggerActorId;
    final source = _text(trace!['parent_source_channel']) ??
        _text(trace!['source_channel']) ??
        movement.triggerSourceChannel;
    final reason = _contextReason(trace!['parent_context']) ??
        _contextReason(trace!['context']) ??
        movement.triggerReason;
    final oldStatus = _text(trace!['old_status']);
    final newStatus = _text(trace!['new_status']);
    final outcome = _text(trace!['parent_outcome']) ?? _text(trace!['outcome']);
    final executor = _text(trace!['executor']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DefinitionRow(
          label: 'Acción',
          value: _actionLabel(action),
        ),
        if (oldStatus != null || newStatus != null)
          _DefinitionRow(
            label: 'Transición',
            value: '${oldStatus ?? '∅'} → ${newStatus ?? '∅'}',
          ),
        if (reason != null) _DefinitionRow(label: 'Motivo', value: reason),
        if (actor != null) _DefinitionRow(label: 'Actor', value: actor),
        if (source != null) _DefinitionRow(label: 'Canal', value: source),
        if (executor != null)
          _DefinitionRow(label: 'Ejecutor', value: executor),
        if (outcome != null) _DefinitionRow(label: 'Resultado', value: outcome),
        if (parentOperationId != null)
          _DefinitionRow(
            label: 'Operación disparadora',
            value: parentOperationId,
          ),
        _DefinitionRow(
          label: 'Operación de stock',
          value: _text(trace!['operation_id']) ?? operationId,
        ),
      ],
    );
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _contextReason(Object? value) {
    if (value is Map) {
      return _text(value['reason']) ?? _text(value['command_reason']);
    }
    return null;
  }

  static String _actionLabel(String? action) {
    return switch (action) {
      'void' => 'Descartar factura',
      'adjust_stock' => 'Ajustar stock',
      'confirm' => 'Confirmar documento',
      'receive' => 'Registrar recepción',
      null => 'Operación registrada',
      _ => action,
    };
  }
}

class _DocumentSection extends StatelessWidget {
  const _DocumentSection({
    required this.movement,
    required this.salesInvoice,
    required this.purchaseInvoice,
    required this.adjustment,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onOpen,
    required this.storeTimezone,
  });

  final StockMovement movement;
  final Invoice? salesInvoice;
  final PurchaseInvoice? purchaseInvoice;
  final StockAdjustmentDetail? adjustment;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpen;
  final String storeTimezone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget child;
    if (loading) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final width in const [150.0, 110.0, 180.0]) ...[
            Container(
              width: width,
              height: 12,
              margin: const EdgeInsets.only(bottom: 9),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ],
      );
    } else if (error != null) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No se pudo cargar el documento.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
              child: const Text('Reintentar'),
            ),
        ],
      );
    } else if (salesInvoice != null) {
      child = _salesSummary(context, salesInvoice!);
    } else if (purchaseInvoice != null) {
      child = _purchaseSummary(context, purchaseInvoice!);
    } else if (adjustment != null) {
      child = _adjustmentDetail(context, adjustment!);
    } else if (movement.hasTypedSourceDocument &&
        movement.sourceDocumentId != null) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Este movimiento conserva la identidad de su '
            '${movement.sourceDocumentDisplay}. El detalle completo pertenece '
            'a su módulo propietario.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (onOpen != null) ...[
            const SizedBox(height: 10),
            _OpenDocumentButton(
              label: 'Abrir ${movement.sourceDocumentDisplay}',
              onOpen: onOpen,
            ),
          ],
        ],
      );
    } else {
      child = Text(
        'Este movimiento no tiene un documento asociado.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      );
    }

    return _InspectorPanel(title: 'Documento', child: child);
  }

  Widget _salesSummary(BuildContext context, Invoice invoice) {
    final theme = Theme.of(context);
    // The one line that touched this product: the fact this ledger cares
    // about. The rest of the invoice belongs to the invoice page.
    InvoiceItem? line;
    for (final item in invoice.items) {
      if (item.productId == movement.productId) {
        line = item;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Factura ${invoice.invoiceNumber}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _StatusMark(
              label: _salesStatusLabel(invoice.status),
              positive: invoice.isPaid,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (invoice.customerName != null)
          _DefinitionRow(label: 'Cliente', value: invoice.customerName!),
        _DefinitionRow(
          label: 'Emisión',
          value: DateFormat('dd/MM/yyyy').format(_storeTime(invoice.date)),
        ),
        if (line != null)
          _DefinitionRow(
            label: 'Este producto',
            value:
                '${_trimQuantity(line.quantity)} × ${ChileanUtils.formatCurrency(line.unitPrice)}',
          ),
        _DefinitionRow(
          label: 'Total',
          value: ChileanUtils.formatCurrency(invoice.total),
        ),
        const SizedBox(height: 10),
        _OpenDocumentButton(label: 'Abrir factura', onOpen: onOpen),
      ],
    );
  }

  Widget _purchaseSummary(BuildContext context, PurchaseInvoice invoice) {
    final theme = Theme.of(context);
    PurchaseInvoiceItem? line;
    for (final item in invoice.items) {
      if (item.productId == movement.productId) {
        line = item;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Factura de compra ${invoice.invoiceNumber}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (invoice.supplierName != null)
          _DefinitionRow(label: 'Proveedor', value: invoice.supplierName!),
        _DefinitionRow(
          label: 'Emisión',
          value: DateFormat('dd/MM/yyyy').format(_storeTime(invoice.date)),
        ),
        _DefinitionRow(
          label: 'Financiero',
          value: _purchaseFinancialState(invoice),
        ),
        _DefinitionRow(
          label: 'Recepción física',
          value: _purchasePhysicalState(invoice),
        ),
        if (line != null)
          _DefinitionRow(
            label: 'Este producto',
            value:
                '${_trimQuantity(line.quantity)} × ${ChileanUtils.formatCurrency(line.unitCost)}',
          ),
        _DefinitionRow(
          label: 'Total',
          value: ChileanUtils.formatCurrency(invoice.total),
        ),
        const SizedBox(height: 10),
        _OpenDocumentButton(label: 'Abrir factura de compra', onOpen: onOpen),
      ],
    );
  }

  /// The adjustment is inventory's own record, so its detail lives here in
  /// full — there is no other module to route to.
  Widget _adjustmentDetail(BuildContext context, StockAdjustmentDetail detail) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final counterpart = [
      if ((detail.counterpartAccountCode ?? '').isNotEmpty)
        detail.counterpartAccountCode,
      if ((detail.counterpartAccountName ?? '').isNotEmpty)
        detail.counterpartAccountName,
    ].whereType<String>().join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DefinitionRow(label: 'Tipo', value: detail.adjustmentTypeLabel),
        _DefinitionRow(label: 'Referencia', value: detail.referenceDisplay),
        _DefinitionRow(
          label: 'Cambio',
          value: detail.quantity >= 0
              ? '+${detail.quantity}'
              : '${detail.quantity}',
        ),
        _DefinitionRow(
          label: 'Resultado',
          value: '${detail.stockBefore} → ${detail.stockAfter}',
        ),
        if (detail.hasAdjustmentOrigin)
          _DefinitionRow(
            label: 'Origen',
            value: detail.adjustmentOriginDisplay!,
          ),
        _DefinitionRow(label: 'Registrado por', value: detail.createdByDisplay),
        _DefinitionRow(
          label: 'Fecha efectiva',
          value: DateFormat('dd/MM/yyyy HH:mm')
              .format(_storeTime(detail.adjustmentDate)),
        ),
        if (detail.reasonDisplay.trim().isNotEmpty)
          _DefinitionRow(label: 'Motivo', value: detail.reasonDisplay),
        const SizedBox(height: 10),
        Divider(height: 1, color: colors.outlineVariant),
        const SizedBox(height: 10),
        Text(
          'Impacto contable',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        _DefinitionRow(
          label: detail.unitCostLabel,
          value: ChileanUtils.formatCurrency(detail.displayedUnitCost),
        ),
        _DefinitionRow(
          label: detail.inventoryValueLabel,
          value: ChileanUtils.formatCurrency(detail.displayedInventoryValue),
        ),
        if (detail.hasPostedJournal) ...[
          _DefinitionRow(label: 'Asiento', value: detail.journalEntryNumber!),
          if ((detail.journalEntryDescription ?? '').isNotEmpty)
            _DefinitionRow(
              label: 'Descripción',
              value: detail.journalEntryDescription!,
            ),
          if (counterpart.isNotEmpty)
            _DefinitionRow(label: 'Cuenta contraparte', value: counterpart),
          _DefinitionRow(
            label: detail.isIncrease
                ? 'Crédito contraparte'
                : 'Débito contraparte',
            value: ChileanUtils.formatCurrency(detail.counterpartAmount),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              detail.accountingImpactMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }

  static String _purchaseFinancialState(PurchaseInvoice invoice) {
    if (invoice.status == PurchaseInvoiceStatus.cancelled) {
      return 'Anulada; se conserva el historial financiero.';
    }
    if (invoice.status == PurchaseInvoiceStatus.paid ||
        (invoice.total > 0 && invoice.paidAmount > 0 && invoice.balance <= 0)) {
      return 'Pagada · ${ChileanUtils.formatCurrency(invoice.paidAmount)}';
    }
    if (invoice.paidAmount > 0) {
      return 'Pago parcial · ${ChileanUtils.formatCurrency(invoice.paidAmount)} '
          'pagado · ${ChileanUtils.formatCurrency(invoice.balance)} pendiente';
    }
    return 'Sin pagos registrados';
  }

  String _purchasePhysicalState(PurchaseInvoice invoice) {
    final fulfillment = invoice.receiptFulfillment;
    if (fulfillment != null) {
      final quantities =
          '${fulfillment.acceptedQuantity}/${fulfillment.expectedQuantity} unidades';
      return switch (fulfillment.state.name) {
        'complete' => 'Recibida · $quantities',
        'closedWithDifference' =>
          'Cerrada con diferencia · $quantities aceptadas',
        'open' => 'Recepción parcial · $quantities aceptadas',
        _ => 'Sin recepción registrada',
      };
    }

    final receivedAt = invoice.receivedDate;
    if (receivedAt != null ||
        invoice.status == PurchaseInvoiceStatus.received) {
      return receivedAt == null
          ? 'Recepción registrada como evidencia histórica'
          : 'Recepción histórica · '
              '${DateFormat('dd/MM/yyyy').format(_storeTime(receivedAt))}';
    }
    return 'Estado físico no incluido en este resumen; abrir la factura para '
        'consultar la evidencia de recepción.';
  }

  static String _salesStatusLabel(InvoiceStatus status) {
    return switch (status.name) {
      'paid' => 'Pagada',
      'posted' => 'Emitida',
      'confirmed' => 'Confirmada',
      'partial' => 'Pago parcial',
      'partially_paid' => 'Pago parcial',
      'draft' => 'Borrador',
      'cancelled' => 'Anulada',
      'overdue' => 'Vencida',
      // Never print an enum name raw at the operator.
      _ => status.name.isEmpty
          ? 'Sin estado'
          : status.name[0].toUpperCase() + status.name.substring(1),
    };
  }

  static String _trimQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  DateTime _storeTime(DateTime instant) {
    return stockMovementStoreTime(
      instant,
      storeTimezone: storeTimezone,
    );
  }
}

class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.label, required this.positive});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = positive ? colors.tertiary : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _OpenDocumentButton extends StatelessWidget {
  const _OpenDocumentButton({required this.label, required this.onOpen});

  final String label;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    if (onOpen == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        onPressed: onOpen,
        icon: const Icon(Icons.north_east, size: 15),
        label: Text(label),
        style: FilledButton.styleFrom(minimumSize: const Size(48, 40)),
      ),
    );
  }
}
