import 'package:flutter/material.dart';

import '../../../shared/services/document_accounting_context_service.dart';
import '../../../shared/widgets/document_accounting_preview.dart';
import '../models/purchase_receipt.dart';
import '../models/purchase_receipt_resolution.dart';
import 'purchase_receipt_records_dropdown.dart';
import 'purchase_receipt_resolution_register.dart';

enum _PurchaseInvoiceEvidenceTab { payments, receipts, resolutions }

class PurchaseInvoiceEvidenceDropdown extends StatefulWidget {
  const PurchaseInvoiceEvidenceDropdown({
    super.key,
    required this.payments,
    required this.receipts,
    this.resolutionCases = const [],
    this.onPaymentTap,
    this.onReceiptTap,
    this.onResolutionCaseTap,
    this.onResolutionDocumentTap,
    this.initiallyExpanded = false,
  });

  final List<DocumentPaymentRecord> payments;
  final List<PurchaseReceiptRecord> receipts;
  final List<PurchaseReceiptResolutionCase> resolutionCases;
  final ValueChanged<DocumentPaymentRecord>? onPaymentTap;
  final ValueChanged<PurchaseReceiptRecord>? onReceiptTap;
  final PurchaseReceiptResolutionCaseTap? onResolutionCaseTap;
  final PurchaseReceiptResolutionDocumentTap? onResolutionDocumentTap;
  final bool initiallyExpanded;

  @override
  State<PurchaseInvoiceEvidenceDropdown> createState() =>
      _PurchaseInvoiceEvidenceDropdownState();
}

class _PurchaseInvoiceEvidenceDropdownState
    extends State<PurchaseInvoiceEvidenceDropdown> {
  late _PurchaseInvoiceEvidenceTab _selectedTab;
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _selectedTab = _initialTab();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant PurchaseInvoiceEvidenceDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_availableTabs().contains(_selectedTab)) {
      _selectedTab = _initialTab();
    }
  }

  _PurchaseInvoiceEvidenceTab _initialTab() {
    if (widget.payments.isNotEmpty) {
      return _PurchaseInvoiceEvidenceTab.payments;
    }
    if (widget.receipts.isNotEmpty) {
      return _PurchaseInvoiceEvidenceTab.receipts;
    }
    return _PurchaseInvoiceEvidenceTab.resolutions;
  }

  List<_PurchaseInvoiceEvidenceTab> _availableTabs() {
    return [
      if (widget.payments.isNotEmpty) _PurchaseInvoiceEvidenceTab.payments,
      if (widget.receipts.isNotEmpty) _PurchaseInvoiceEvidenceTab.receipts,
      if (widget.resolutionCases.isNotEmpty)
        _PurchaseInvoiceEvidenceTab.resolutions,
    ];
  }

  void _selectTab(_PurchaseInvoiceEvidenceTab tab) {
    setState(() {
      _selectedTab = tab;
      _isExpanded = true;
    });
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _availableTabs();
    if (tabs.isEmpty) return const SizedBox.shrink();
    final pendingResolutionCount = widget.resolutionCases
        .where(
          (resolutionCase) =>
              resolutionCase.openQuantity > 0 &&
              (resolutionCase.effectiveStatus == 'open' ||
                  resolutionCase.effectiveStatus == 'partially_resolved'),
        )
        .length;

    return Material(
      key: const ValueKey('purchase-invoice-evidence-dropdown'),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFDCE3EF)),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey(
                      'purchase-invoice-evidence-tab-scroll',
                    ),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final tab in tabs)
                          _EvidenceTabButton(
                            key: ValueKey(
                              'purchase-invoice-evidence-tab-${tab.name}',
                            ),
                            label: switch (tab) {
                              _PurchaseInvoiceEvidenceTab.payments => 'Pagos',
                              _PurchaseInvoiceEvidenceTab.receipts =>
                                'Recepciones',
                              _PurchaseInvoiceEvidenceTab.resolutions =>
                                'Diferencias',
                            },
                            semanticLabel: switch (tab) {
                              _PurchaseInvoiceEvidenceTab.payments =>
                                'Pagos realizados',
                              _PurchaseInvoiceEvidenceTab.receipts =>
                                'Recepciones de stock',
                              _PurchaseInvoiceEvidenceTab.resolutions =>
                                'Diferencias y resoluciones',
                            },
                            count: switch (tab) {
                              _PurchaseInvoiceEvidenceTab.payments =>
                                widget.payments.length,
                              _PurchaseInvoiceEvidenceTab.receipts =>
                                widget.receipts.length,
                              _PurchaseInvoiceEvidenceTab.resolutions =>
                                widget.resolutionCases.length,
                            },
                            pendingCount:
                                tab == _PurchaseInvoiceEvidenceTab.resolutions
                                    ? pendingResolutionCount
                                    : 0,
                            selected: tab == _selectedTab,
                            expanded: tab == _selectedTab && _isExpanded,
                            onTap: () => _selectTab(tab),
                          ),
                      ],
                    ),
                  ),
                ),
                _DisclosureButton(
                  expanded: _isExpanded,
                  onPressed: _toggleExpanded,
                ),
              ],
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: EdgeInsets.fromLTRB(
                  constraints.maxWidth < 480 ? 8 : 14,
                  0,
                  constraints.maxWidth < 480 ? 8 : 14,
                  constraints.maxWidth < 480 ? 8 : 14,
                ),
                child: switch (_selectedTab) {
                  _PurchaseInvoiceEvidenceTab.payments =>
                    DocumentPaymentRecordsTable(
                      payments: widget.payments,
                      onPaymentTap: widget.onPaymentTap,
                    ),
                  _PurchaseInvoiceEvidenceTab.receipts =>
                    PurchaseReceiptRecordsTable(
                      receipts: widget.receipts,
                      onReceiptTap: widget.onReceiptTap,
                    ),
                  _PurchaseInvoiceEvidenceTab.resolutions =>
                    PurchaseReceiptResolutionTable(
                      cases: widget.resolutionCases,
                      onCaseTap: widget.onResolutionCaseTap,
                      onDocumentTap: widget.onResolutionDocumentTap,
                    ),
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceTabButton extends StatelessWidget {
  const _EvidenceTabButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.count,
    required this.pendingCount,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final int count;
  final int pendingCount;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      expanded: expanded,
      label: '$semanticLabel, $count ${count == 1 ? 'registro' : 'registros'}'
          '${pendingCount > 0 ? ', $pendingCount pendientes' : ''}',
      child: Tooltip(
        message: semanticLabel,
        child: InkWell(
          onTap: onTap,
          hoverColor: const Color(0xFFF8FAFC),
          focusColor: const Color(0xFFEAF1F3),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color:
                      selected ? const Color(0xFF235466) : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF235466)
                        : const Color(0xFF475569),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  key: ValueKey('evidence-count-$semanticLabel'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF235466)
                          : const Color(0xFF52606A),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message:
                        '$pendingCount ${pendingCount == 1 ? 'diferencia pendiente' : 'diferencias pendientes'}',
                    child: const SizedBox.square(
                      dimension: 6,
                      child: DecoratedBox(
                        key: ValueKey(
                          'purchase-invoice-evidence-pending-indicator',
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFFB7791F),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisclosureButton extends StatelessWidget {
  const _DisclosureButton({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      expanded: expanded,
      child: Tooltip(
        message: expanded ? 'Contraer registros' : 'Mostrar registros',
        child: IconButton(
          key: const ValueKey('purchase-invoice-evidence-disclosure'),
          onPressed: onPressed,
          icon: AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 160),
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }
}
