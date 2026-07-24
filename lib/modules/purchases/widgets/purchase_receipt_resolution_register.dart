import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/purchase_receipt_resolution.dart';

typedef PurchaseReceiptResolutionCaseTap = void Function(
  PurchaseReceiptResolutionCase resolutionCase,
);

enum PurchaseReceiptResolutionDocumentKind {
  creditNote,
  laterReceipt,
  documentedLoss,
  documentedLossReversal,
  supplierReturn,
  supplierRefund,
}

class PurchaseReceiptResolutionDocumentReference {
  const PurchaseReceiptResolutionDocumentReference({
    required this.kind,
    required this.id,
    required this.label,
    this.canNavigate = true,
  });

  final PurchaseReceiptResolutionDocumentKind kind;
  final String id;
  final String label;
  final bool canNavigate;
}

typedef PurchaseReceiptResolutionDocumentTap = void Function(
  PurchaseReceiptResolutionCase resolutionCase,
  PurchaseReceiptResolutionAllocation allocation,
  PurchaseReceiptResolutionDocumentReference document,
);

enum _ResolutionCaseState {
  pending,
  partiallyResolved,
  resolved,
  voided,
  inconsistent,
}

_ResolutionCaseState _caseState(PurchaseReceiptResolutionCase item) {
  if (item.effectiveStatus == 'voided') {
    return _ResolutionCaseState.voided;
  }
  if (item.effectiveStatus == 'resolved' &&
      item.openQuantity == 0 &&
      item.resolvedQuantity == item.reportedQuantity) {
    return _ResolutionCaseState.resolved;
  }
  if (item.effectiveStatus == 'partially_resolved' &&
      item.openQuantity > 0 &&
      item.resolvedQuantity > 0) {
    return _ResolutionCaseState.partiallyResolved;
  }
  if (item.effectiveStatus == 'open' &&
      item.openQuantity > 0 &&
      item.resolvedQuantity == 0) {
    return _ResolutionCaseState.pending;
  }
  return _ResolutionCaseState.inconsistent;
}

bool _isPendingState(_ResolutionCaseState state) =>
    state == _ResolutionCaseState.pending ||
    state == _ResolutionCaseState.partiallyResolved;

class PurchaseReceiptResolutionRegister extends StatelessWidget {
  const PurchaseReceiptResolutionRegister({
    super.key,
    required this.cases,
    this.onCaseTap,
    this.onDocumentTap,
    this.initiallyExpanded = true,
  });

  final List<PurchaseReceiptResolutionCase> cases;
  final PurchaseReceiptResolutionCaseTap? onCaseTap;
  final PurchaseReceiptResolutionDocumentTap? onDocumentTap;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (cases.isEmpty) return const SizedBox.shrink();
    final states = cases.map(_caseState).toList(growable: false);
    final pendingCount = states.where(_isPendingState).length;
    final resolvedCount =
        states.where((state) => state == _ResolutionCaseState.resolved).length;
    final voidedCount =
        states.where((state) => state == _ResolutionCaseState.voided).length;
    final reviewCount = states
        .where((state) => state == _ResolutionCaseState.inconsistent)
        .length;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xFFD8DEE3)),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: EdgeInsets.zero,
          iconColor: const Color(0xFF52606A),
          collapsedIconColor: const Color(0xFF52606A),
          title: Row(
            children: [
              const Flexible(
                child: Text(
                  'Diferencias y resoluciones',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF26323A),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _RegisterSummary(
                pendingCount: pendingCount,
                resolvedCount: resolvedCount,
                voidedCount: voidedCount,
                reviewCount: reviewCount,
              ),
            ],
          ),
          children: [
            PurchaseReceiptResolutionTable(
              cases: cases,
              onCaseTap: onCaseTap,
              onDocumentTap: onDocumentTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterSummary extends StatelessWidget {
  const _RegisterSummary({
    required this.pendingCount,
    required this.resolvedCount,
    required this.voidedCount,
    required this.reviewCount,
  });

  final int pendingCount;
  final int resolvedCount;
  final int voidedCount;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    final bool showPendingDot;
    if (pendingCount > 0) {
      label = '$pendingCount '
          '${pendingCount == 1 ? 'pendiente' : 'pendientes'}';
      color = const Color(0xFF76552A);
      showPendingDot = true;
    } else if (reviewCount > 0) {
      label = '$reviewCount por revisar';
      color = const Color(0xFF874B4E);
      showPendingDot = false;
    } else if (resolvedCount > 0 && voidedCount > 0) {
      label = '$resolvedCount '
          '${resolvedCount == 1 ? 'resuelta' : 'resueltas'} · '
          '$voidedCount sin efecto';
      color = const Color(0xFF52606A);
      showPendingDot = false;
    } else if (resolvedCount > 0) {
      label = '$resolvedCount '
          '${resolvedCount == 1 ? 'resuelta' : 'resueltas'}';
      color = const Color(0xFF2F6F62);
      showPendingDot = false;
    } else {
      label = '$voidedCount sin efecto';
      color = const Color(0xFF68747D);
      showPendingDot = false;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPendingDot) ...[
          const SizedBox.square(
            dimension: 6,
            child: DecoratedBox(
              key: ValueKey('purchase-receipt-resolution-pending-indicator'),
              decoration: BoxDecoration(
                color: Color(0xFFB7791F),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class PurchaseReceiptResolutionTable extends StatelessWidget {
  const PurchaseReceiptResolutionTable({
    super.key,
    required this.cases,
    this.onCaseTap,
    this.onDocumentTap,
  });

  final List<PurchaseReceiptResolutionCase> cases;
  final PurchaseReceiptResolutionCaseTap? onCaseTap;
  final PurchaseReceiptResolutionDocumentTap? onDocumentTap;

  @override
  Widget build(BuildContext context) {
    if (cases.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedWidth && constraints.maxWidth < 760) {
          return Column(
            key: const ValueKey('purchase-receipt-resolution-compact-list'),
            children: [
              for (final resolutionCase in cases)
                _CompactResolutionCaseRow(
                  resolutionCase: resolutionCase,
                  onCaseTap: onCaseTap,
                  onDocumentTap: onDocumentTap,
                ),
            ],
          );
        }

        const minTableWidth = 760.0;
        final tableWidth = constraints.hasBoundedWidth
            ? math.max(constraints.maxWidth, minTableWidth)
            : minTableWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                const _RegisterHeader(),
                for (final resolutionCase in cases)
                  _ResolutionCaseRow(
                    resolutionCase: resolutionCase,
                    onCaseTap: onCaseTap,
                    onDocumentTap: onDocumentTap,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RegisterHeader extends StatelessWidget {
  const _RegisterHeader();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xFFF1F4F6),
        border: Border(
          top: BorderSide(color: Color(0xFFD8DEE3)),
          bottom: BorderSide(color: Color(0xFFD8DEE3)),
        ),
      ),
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                flex: 45,
                child: _HeaderLabel('CASO / PRODUCTO'),
              ),
              Expanded(
                flex: 18,
                child: _HeaderLabel('DIFERENCIA'),
              ),
              Expanded(
                flex: 27,
                child: _HeaderLabel('RESOLUCIÓN'),
              ),
              SizedBox(width: 88),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF52606A),
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _ResolutionCaseRow extends StatelessWidget {
  const _ResolutionCaseRow({
    required this.resolutionCase,
    required this.onCaseTap,
    required this.onDocumentTap,
  });

  final PurchaseReceiptResolutionCase resolutionCase;
  final PurchaseReceiptResolutionCaseTap? onCaseTap;
  final PurchaseReceiptResolutionDocumentTap? onDocumentTap;

  @override
  Widget build(BuildContext context) {
    final state = _caseState(resolutionCase);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE3E8EC)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 45,
              child: _CaseIdentity(resolutionCase: resolutionCase),
            ),
            Expanded(
              flex: 18,
              child: _CaseStateLabel(
                resolutionCase: resolutionCase,
                state: state,
              ),
            ),
            Expanded(
              flex: 27,
              child: _ResolutionEvidence(
                resolutionCase: resolutionCase,
                state: state,
                onDocumentTap: onDocumentTap,
              ),
            ),
            SizedBox(
              width: 88,
              child: TextButton(
                onPressed:
                    onCaseTap == null ? null : () => onCaseTap!(resolutionCase),
                child: Text(_caseActionLabel(state)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactResolutionCaseRow extends StatelessWidget {
  const _CompactResolutionCaseRow({
    required this.resolutionCase,
    required this.onCaseTap,
    required this.onDocumentTap,
  });

  final PurchaseReceiptResolutionCase resolutionCase;
  final PurchaseReceiptResolutionCaseTap? onCaseTap;
  final PurchaseReceiptResolutionDocumentTap? onDocumentTap;

  @override
  Widget build(BuildContext context) {
    final state = _caseState(resolutionCase);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE3E8EC)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CaseIdentity(resolutionCase: resolutionCase),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onCaseTap == null
                      ? null
                      : () => onCaseTap!(resolutionCase),
                  child: Text(_caseActionLabel(state)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _CaseStateLabel(
              resolutionCase: resolutionCase,
              state: state,
            ),
            const SizedBox(height: 8),
            _ResolutionEvidence(
              resolutionCase: resolutionCase,
              state: state,
              onDocumentTap: onDocumentTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _CaseIdentity extends StatelessWidget {
  const _CaseIdentity({required this.resolutionCase});

  final PurchaseReceiptResolutionCase resolutionCase;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if ((resolutionCase.purchaseReceiptNumber ?? '').isNotEmpty)
        resolutionCase.purchaseReceiptNumber!,
      if ((resolutionCase.productSku ?? '').isNotEmpty)
        'SKU ${resolutionCase.productSku}',
    ].join(' · ');
    final reason = resolutionCase.discrepancyReason?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${resolutionCase.number} · ${resolutionCase.productName}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF26323A),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            metadata,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF68747D),
              fontSize: 11.5,
            ),
          ),
        ],
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            'Motivo: $reason',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF68747D),
              fontSize: 11.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _CaseStateLabel extends StatelessWidget {
  const _CaseStateLabel({
    required this.resolutionCase,
    required this.state,
  });

  final PurchaseReceiptResolutionCase resolutionCase;
  final _ResolutionCaseState state;

  @override
  Widget build(BuildContext context) {
    final String detail;
    final Color detailColor;
    final FontWeight detailWeight;
    switch (state) {
      case _ResolutionCaseState.pending:
        detail = '${resolutionCase.openQuantity} de '
            '${resolutionCase.reportedQuantity} pendientes';
        detailColor = const Color(0xFF76552A);
        detailWeight = FontWeight.w700;
        break;
      case _ResolutionCaseState.partiallyResolved:
        detail = '${resolutionCase.resolvedQuantity} resueltas · '
            '${resolutionCase.openQuantity} pendientes';
        detailColor = const Color(0xFF76552A);
        detailWeight = FontWeight.w700;
        break;
      case _ResolutionCaseState.resolved:
        detail = '${resolutionCase.resolvedQuantity} de '
            '${resolutionCase.reportedQuantity} resueltas';
        detailColor = const Color(0xFF2F6F62);
        detailWeight = FontWeight.w600;
        break;
      case _ResolutionCaseState.voided:
        detail = 'Recepción anulada';
        detailColor = const Color(0xFF68747D);
        detailWeight = FontWeight.w600;
        break;
      case _ResolutionCaseState.inconsistent:
        detail = 'Requiere revisión';
        detailColor = const Color(0xFF874B4E);
        detailWeight = FontWeight.w700;
        break;
    }

    return Column(
      key: ValueKey('resolution-case-state-${resolutionCase.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          resolutionCase.kind.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF52606A),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: detailColor,
            fontSize: 11.5,
            fontWeight: detailWeight,
          ),
        ),
      ],
    );
  }
}

class _ResolutionEvidence extends StatelessWidget {
  const _ResolutionEvidence({
    required this.resolutionCase,
    required this.state,
    required this.onDocumentTap,
  });

  final PurchaseReceiptResolutionCase resolutionCase;
  final _ResolutionCaseState state;
  final PurchaseReceiptResolutionDocumentTap? onDocumentTap;

  @override
  Widget build(BuildContext context) {
    final allocations = resolutionCase.allocations;
    if (allocations.isEmpty) {
      final label = switch (state) {
        _ResolutionCaseState.pending ||
        _ResolutionCaseState.partiallyResolved =>
          'Sin resolución registrada',
        _ResolutionCaseState.resolved => 'Sin evidencia vinculada',
        _ResolutionCaseState.voided => 'Sin resolución aplicada',
        _ResolutionCaseState.inconsistent => 'Evidencia incompleta',
      };
      return Text(
        label,
        style: const TextStyle(
          color: Color(0xFF68747D),
          fontSize: 12,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < allocations.length; index++) ...[
          if (index > 0) const SizedBox(height: 5),
          _AllocationEvidence(
            allocation: allocations[index],
            sourceReceiptVoided: state == _ResolutionCaseState.voided,
            onDocumentTap: onDocumentTap == null
                ? null
                : (document) => onDocumentTap!(
                      resolutionCase,
                      allocations[index],
                      document,
                    ),
          ),
        ],
      ],
    );
  }
}

String _caseActionLabel(_ResolutionCaseState state) => switch (state) {
      _ResolutionCaseState.pending ||
      _ResolutionCaseState.partiallyResolved =>
        'Abrir caso',
      _ResolutionCaseState.inconsistent => 'Revisar',
      _ResolutionCaseState.resolved => 'Ver registro',
      _ResolutionCaseState.voided => 'Ver recepción',
    };

class _AllocationEvidence extends StatelessWidget {
  const _AllocationEvidence({
    required this.allocation,
    required this.sourceReceiptVoided,
    required this.onDocumentTap,
  });

  final PurchaseReceiptResolutionAllocation allocation;
  final bool sourceReceiptVoided;
  final ValueChanged<PurchaseReceiptResolutionDocumentReference>? onDocumentTap;

  @override
  Widget build(BuildContext context) {
    final documents = _documents(allocation);
    final statusLabel = _allocationStatusLabel(
      allocation,
      sourceReceiptVoided: sourceReceiptVoided,
    );

    return Wrap(
      key: ValueKey('resolution-allocation-${allocation.id}'),
      spacing: 8,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final document in documents)
          _DocumentLink(
            document: document,
            active: allocation.isActive,
            onTap:
                onDocumentTap == null ? null : () => onDocumentTap!(document),
          ),
        Text(
          statusLabel,
          style: TextStyle(
            color: _allocationStatusColor(
              allocation,
              sourceReceiptVoided: sourceReceiptVoided,
            ),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  List<PurchaseReceiptResolutionDocumentReference> _documents(
    PurchaseReceiptResolutionAllocation allocation,
  ) {
    final documents = <PurchaseReceiptResolutionDocumentReference>[];
    switch (allocation.outcome) {
      case PurchaseReceiptResolutionOutcome.creditNote:
        documents.add(
          PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.creditNote,
            id: allocation.purchaseCreditNoteId ?? '',
            label: allocation.purchaseCreditNoteNumber ?? 'Nota de crédito',
          ),
        );
        break;
      case PurchaseReceiptResolutionOutcome.laterDelivery:
        documents.add(
          PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.laterReceipt,
            id: allocation.laterPurchaseReceiptId ?? '',
            label: allocation.laterPurchaseReceiptNumber ?? 'Entrega posterior',
          ),
        );
        break;
      case PurchaseReceiptResolutionOutcome.documentedLoss:
        documents.add(
          PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.documentedLoss,
            id: allocation.lossJournalEntryId ?? '',
            label: allocation.lossJournalEntryNumber == null
                ? 'Pérdida documentada · sin asiento enlazado'
                : 'Asiento ${allocation.lossJournalEntryNumber}',
            canNavigate: false,
          ),
        );
        break;
      case PurchaseReceiptResolutionOutcome.documentedLossReversal:
        documents.add(
          PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.documentedLossReversal,
            id: allocation.lossJournalEntryId ?? '',
            label: allocation.lossJournalEntryNumber == null
                ? 'Reversa de pérdida'
                : 'Reversa ${allocation.lossJournalEntryNumber}',
            canNavigate: false,
          ),
        );
        break;
      case PurchaseReceiptResolutionOutcome.unknown:
        documents.add(
          const PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.documentedLoss,
            id: '',
            label: 'Resolución no reconocida',
            canNavigate: false,
          ),
        );
        break;
    }
    if ((allocation.supplierReturnNumber ?? '').isNotEmpty) {
      documents.add(
        PurchaseReceiptResolutionDocumentReference(
          kind: PurchaseReceiptResolutionDocumentKind.supplierReturn,
          id: allocation.supplierReturnId ?? '',
          label: 'Dev. ${allocation.supplierReturnNumber}'
              '${_voidedStatusSuffix(allocation.supplierReturnStatus)}',
        ),
      );
    }
    for (final refund in allocation.supplierRefunds) {
      documents.add(
        PurchaseReceiptResolutionDocumentReference(
          kind: PurchaseReceiptResolutionDocumentKind.supplierRefund,
          id: refund.id,
          label: 'Reembolso ${refund.number}'
              '${_voidedStatusSuffix(refund.status)}',
        ),
      );
    }
    return documents;
  }
}

String _allocationStatusLabel(
  PurchaseReceiptResolutionAllocation allocation, {
  required bool sourceReceiptVoided,
}) {
  if (allocation.outcome ==
          PurchaseReceiptResolutionOutcome.documentedLossReversal ||
      allocation.effectiveStatus == 'reversal') {
    return 'Reversa registrada';
  }
  if (sourceReceiptVoided && !allocation.isActive) {
    return 'Sin efecto por recepción anulada';
  }
  if (allocation.isActive) return 'Aplicada';
  if (allocation.effectiveStatus == 'voided') {
    return allocation.outcome == PurchaseReceiptResolutionOutcome.documentedLoss
        ? 'Revertida'
        : 'Anulada';
  }
  if (allocation.effectiveStatus == 'missing') {
    return 'Documento no disponible';
  }
  return 'Sin efecto';
}

Color _allocationStatusColor(
  PurchaseReceiptResolutionAllocation allocation, {
  required bool sourceReceiptVoided,
}) {
  if (allocation.isActive) return const Color(0xFF2F6F62);
  if (allocation.outcome ==
          PurchaseReceiptResolutionOutcome.documentedLossReversal ||
      allocation.effectiveStatus == 'reversal' ||
      sourceReceiptVoided) {
    return const Color(0xFF68747D);
  }
  if (allocation.effectiveStatus == 'voided') {
    return const Color(0xFF874B4E);
  }
  return const Color(0xFF76552A);
}

String _voidedStatusSuffix(String? status) {
  return switch (status?.toLowerCase()) {
    'voided' || 'cancelled' || 'canceled' => ' (anulado)',
    _ => '',
  };
}

class _DocumentLink extends StatelessWidget {
  const _DocumentLink({
    required this.document,
    required this.active,
    required this.onTap,
  });

  final PurchaseReceiptResolutionDocumentReference document;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final canOpen =
        onTap != null && document.canNavigate && document.id.isNotEmpty;
    return Semantics(
      button: canOpen,
      label: canOpen ? 'Abrir ${document.label}' : document.label,
      child: InkWell(
        onTap: canOpen ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            document.label,
            style: TextStyle(
              color:
                  canOpen ? const Color(0xFF235466) : const Color(0xFF52606A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              decoration: canOpen ? TextDecoration.underline : null,
              decorationColor: const Color(0xFF235466),
              decorationStyle: active
                  ? TextDecorationStyle.solid
                  : TextDecorationStyle.dotted,
            ),
          ),
        ),
      ),
    );
  }
}
