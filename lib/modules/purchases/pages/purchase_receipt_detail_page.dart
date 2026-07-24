import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../models/purchase_credit_note.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_receipt.dart';
import '../models/purchase_receipt_resolution.dart';
import '../services/purchase_credit_note_service.dart';
import '../services/purchase_receipt_resolution_service.dart';
import '../services/purchase_receiving_service.dart';
import '../services/purchase_service.dart';
import '../services/purchase_supplier_return_service.dart';
import '../widgets/purchase_receipt_detail_view.dart';
import '../widgets/purchase_receipt_resolution_register.dart';
import 'purchase_credit_note_page.dart';
import 'purchase_receiving_page.dart';
import 'purchase_supplier_return_page.dart';

class PurchaseReceiptDetailPage extends StatefulWidget {
  const PurchaseReceiptDetailPage({
    super.key,
    required this.receiptId,
  });

  final String receiptId;

  @override
  State<PurchaseReceiptDetailPage> createState() =>
      _PurchaseReceiptDetailPageState();
}

class _PurchaseReceiptDetailPageState extends State<PurchaseReceiptDetailPage> {
  final PurchaseReceivingService _receivingService = PurchaseReceivingService();
  final PurchaseReceiptResolutionService _resolutionService =
      PurchaseReceiptResolutionService();

  PurchaseReceiptDetailRecord? _receipt;
  PurchaseInvoice? _invoice;
  List<PurchaseReceiptResolutionCase> _resolutionCases = const [];
  Map<String, String> _productImageUrls = const {};
  bool _loading = true;
  bool _showingLaterDelivery = false;
  String? _focusedCreditNoteId;
  String? _focusedPurchaseRefundId;
  String? _focusedSupplierReturnId;
  bool _submittingResolution = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final purchaseService = context.read<PurchaseService>();
      final casesFuture =
          _resolutionService.getCasesForReceipt(widget.receiptId);
      final receipt =
          await _receivingService.getReceiptDetail(widget.receiptId);
      if (receipt == null) {
        throw StateError(
          'La recepción no existe o no pertenece a la empresa activa.',
        );
      }
      final productImagesFuture = _loadProductImages(
        receipt.lines.map((line) => line.productId ?? ''),
      );
      final invoice = await purchaseService.getPurchaseInvoice(
        receipt.purchaseInvoiceId,
        refresh: true,
      );
      if (invoice == null) {
        throw StateError(
          'No se encontró la factura vinculada a esta recepción.',
        );
      }
      final cases = await casesFuture;
      final productImageUrls = await productImagesFuture;
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _invoice = invoice;
        _resolutionCases = cases;
        _productImageUrls = productImageUrls;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<Map<String, String>> _loadProductImages(
    Iterable<String> productIds,
  ) async {
    try {
      return await _receivingService.getProductImageUrls(productIds);
    } catch (error) {
      debugPrint(
        'No se pudieron cargar miniaturas del registro de recepción: $error',
      );
      return const {};
    }
  }

  Future<void> _resolveCase(
      PurchaseReceiptResolutionCase resolutionCase) async {
    if (!resolutionCase.isOpen || _submittingResolution) return;
    final outcome = await _selectResolutionOutcome(resolutionCase);
    if (outcome == null || !mounted) return;
    switch (outcome) {
      case PurchaseReceiptResolutionOutcome.creditNote:
        await _openCreditNoteResolution(resolutionCase);
        break;
      case PurchaseReceiptResolutionOutcome.laterDelivery:
        setState(() => _showingLaterDelivery = true);
        break;
      case PurchaseReceiptResolutionOutcome.documentedLoss:
        await _recordDocumentedLoss(resolutionCase);
        break;
      case PurchaseReceiptResolutionOutcome.documentedLossReversal:
      case PurchaseReceiptResolutionOutcome.unknown:
        break;
    }
  }

  Future<PurchaseReceiptResolutionOutcome?> _selectResolutionOutcome(
    PurchaseReceiptResolutionCase resolutionCase,
  ) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    if (compact) {
      return showModalBottomSheet<PurchaseReceiptResolutionOutcome>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            child: _ResolutionOutcomePicker(
              resolutionCase: resolutionCase,
              onSelected: (outcome) => Navigator.pop(sheetContext, outcome),
              onCancel: () => Navigator.pop(sheetContext),
            ),
          ),
        ),
      );
    }
    return showDialog<PurchaseReceiptResolutionOutcome>(
      context: context,
      builder: (dialogContext) {
        final availableHeight = MediaQuery.sizeOf(dialogContext).height * 0.82;
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFD8DEE3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: availableHeight,
            ),
            child: SingleChildScrollView(
              child: _ResolutionOutcomePicker(
                resolutionCase: resolutionCase,
                onSelected: (outcome) => Navigator.pop(dialogContext, outcome),
                onCancel: () => Navigator.pop(dialogContext),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCreditNoteResolution(
    PurchaseReceiptResolutionCase resolutionCase,
  ) async {
    final invoice = _invoice;
    if (invoice == null) return;
    final result = await Navigator.of(context).push<PurchaseCreditNoteResult>(
      MaterialPageRoute(
        builder: (_) => PurchaseCreditNotePage(
          invoice: invoice,
          service: PurchaseCreditNoteService(),
          initialReceiptResolutionCaseId: resolutionCase.id,
          initialSourceLineIndex: resolutionCase.sourceLineIndex,
          initialResolutionQuantity: resolutionCase.openQuantity,
          initialResolutionLabel: resolutionCase.number,
          initialReceiptId: resolutionCase.purchaseReceiptId,
          initialReceiptNumber: _receipt?.number,
        ),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _recordDocumentedLoss(
    PurchaseReceiptResolutionCase resolutionCase,
  ) async {
    final reasonController = TextEditingController();
    final notesController = TextEditingController();
    var quantity = resolutionCase.openQuantity;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Registrar pérdida documentada'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se cargará la cuenta de pérdidas y se abonará Inventarios '
                'por el costo de estas unidades. No se descontará stock: '
                'estas unidades nunca ingresaron físicamente.',
              ),
              const SizedBox(height: 10),
              const Text(
                'Usa esta opción únicamente cuando el proveedor no compensará '
                'la diferencia. La operación quedará auditada y podrá '
                'revertirse con un asiento inverso.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: quantity.toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Cantidad (máx. ${resolutionCase.openQuantity})',
                ),
                onChanged: (value) => quantity = int.tryParse(value) ?? 0,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Motivo obligatorio',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Evidencia o nota interna (opcional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registrar ajuste'),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim();
    final notes = notesController.text.trim();
    final documentedReason =
        notes.isEmpty ? reason : '$reason · Evidencia: $notes';
    reasonController.dispose();
    notesController.dispose();
    if (confirmed != true || !mounted) return;
    if (quantity <= 0 ||
        quantity > resolutionCase.openQuantity ||
        reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Revisa la cantidad y escribe un motivo.'),
        ),
      );
      return;
    }

    setState(() => _submittingResolution = true);
    try {
      await _resolutionService.resolveWithDocumentedLoss(
        invoiceId: resolutionCase.purchaseInvoiceId,
        caseId: resolutionCase.id,
        quantity: quantity,
        effectiveAt: DateTime.now(),
        reason: documentedReason,
        idempotencyKey: const Uuid().v4(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pérdida documentada registrada sin movimiento de stock.',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar la pérdida: $error')),
      );
    } finally {
      if (mounted) setState(() => _submittingResolution = false);
    }
  }

  Future<void> _openAllocation(
    PurchaseReceiptResolutionAllocation allocation,
  ) async {
    final creditNoteId = allocation.purchaseCreditNoteId;
    if (creditNoteId != null && creditNoteId.isNotEmpty) {
      setState(() => _focusedCreditNoteId = creditNoteId);
      return;
    }
    final laterReceiptId = allocation.laterPurchaseReceiptId;
    if (laterReceiptId != null && laterReceiptId.isNotEmpty) {
      await context.push(
        '/purchases/receipts/${Uri.encodeComponent(laterReceiptId)}',
      );
      if (mounted) await _load();
    }
  }

  Future<void> _openResolutionDocument(
    PurchaseReceiptResolutionCase _,
    PurchaseReceiptResolutionAllocation allocation,
    PurchaseReceiptResolutionDocumentReference document,
  ) async {
    switch (document.kind) {
      case PurchaseReceiptResolutionDocumentKind.creditNote:
      case PurchaseReceiptResolutionDocumentKind.supplierRefund:
        final creditNoteId = allocation.purchaseCreditNoteId;
        if (creditNoteId != null && creditNoteId.isNotEmpty) {
          setState(() {
            _focusedCreditNoteId = creditNoteId;
            _focusedPurchaseRefundId = document.kind ==
                    PurchaseReceiptResolutionDocumentKind.supplierRefund
                ? document.id
                : null;
            _focusedSupplierReturnId = null;
          });
          return;
        }
        break;
      case PurchaseReceiptResolutionDocumentKind.laterReceipt:
        if (document.id.isNotEmpty) {
          await context.push(
            '/purchases/receipts/${Uri.encodeComponent(document.id)}',
          );
          if (mounted) await _load();
          return;
        }
        break;
      case PurchaseReceiptResolutionDocumentKind.supplierReturn:
        if (document.id.isNotEmpty) {
          setState(() {
            _focusedSupplierReturnId = document.id;
            _focusedCreditNoteId = null;
            _focusedPurchaseRefundId = null;
          });
          return;
        }
        break;
      case PurchaseReceiptResolutionDocumentKind.documentedLoss:
      case PurchaseReceiptResolutionDocumentKind.documentedLossReversal:
        return;
    }

    await _openAllocation(allocation);
  }

  Future<void> _voidLoss(
    PurchaseReceiptResolutionAllocation allocation,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Revertir pérdida documentada'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se publicará un asiento inverso y la diferencia volverá a '
                'quedar abierta. No se moverá stock.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration:
                    const InputDecoration(labelText: 'Motivo obligatorio'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Conservar ajuste'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Crear reversa'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _submittingResolution = true);
    try {
      await _resolutionService.voidDocumentedLoss(
        resolutionGroupId: allocation.resolutionGroupId,
        reason: reason,
        idempotencyKey: const Uuid().v4(),
      );
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo revertir el ajuste: $error')),
      );
    } finally {
      if (mounted) setState(() => _submittingResolution = false);
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final invoiceId = _receipt?.purchaseInvoiceId;
    context.go(
      invoiceId == null || invoiceId.isEmpty
          ? '/purchases'
          : '/purchases/$invoiceId',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: _focusedSupplierReturnId != null && _invoice != null
          ? PurchaseSupplierReturnPage(
              invoice: _invoice!,
              service: PurchaseSupplierReturnService(),
              focusReturnId: _focusedSupplierReturnId,
              embedded: true,
              onClose: () async {
                setState(() => _focusedSupplierReturnId = null);
                await _load();
              },
            )
          : _focusedCreditNoteId != null && _invoice != null
              ? PurchaseCreditNotePage(
                  invoice: _invoice!,
                  service: PurchaseCreditNoteService(),
                  focusCreditNoteId: _focusedCreditNoteId,
                  focusRefundId: _focusedPurchaseRefundId,
                  initialReceiptId: widget.receiptId,
                  initialReceiptNumber: _receipt?.number,
                  embedded: true,
                  onClose: () async {
                    setState(() {
                      _focusedCreditNoteId = null;
                      _focusedPurchaseRefundId = null;
                    });
                    await _load();
                  },
                )
              : _showingLaterDelivery && _invoice != null
                  ? PurchaseReceivingWorkspace(
                      invoice: _invoice!,
                      onCancel: () =>
                          setState(() => _showingLaterDelivery = false),
                      onCompleted: (_) async {
                        setState(() => _showingLaterDelivery = false);
                        await _load();
                      },
                    )
                  : _loading
                      ? const Center(child: BrandedLoading())
                      : _receipt == null || _invoice == null
                          ? _buildFailure()
                          : PurchaseReceiptDetailView(
                              receipt: _receipt!,
                              invoice: _invoice!,
                              onClose: _close,
                              onRefresh: _load,
                              resolutionCases: _resolutionCases,
                              productImageUrls: _productImageUrls,
                              resolving: _submittingResolution,
                              onResolveCase: _resolveCase,
                              onOpenAllocation: _openAllocation,
                              onResolutionDocumentTap: _openResolutionDocument,
                              onVoidLoss: _voidLoss,
                              onOpenInvoice: () => context.push(
                                '/purchases/${_receipt!.purchaseInvoiceId}',
                              ),
                            ),
    );
  }

  Widget _buildFailure() {
    return ColoredBox(
      color: const Color(0xFFF6F8FA),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 48,
                  color: Color(0xFF68747D),
                ),
                const SizedBox(height: 14),
                Text(
                  _error ?? 'No se pudo cargar la recepción.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF37434B),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _close,
                      child: const Text('Volver a compras'),
                    ),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResolutionOutcomePicker extends StatelessWidget {
  const _ResolutionOutcomePicker({
    required this.resolutionCase,
    required this.onSelected,
    required this.onCancel,
  });

  final PurchaseReceiptResolutionCase resolutionCase;
  final ValueChanged<PurchaseReceiptResolutionOutcome> onSelected;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resolver ${resolutionCase.number}',
                        style: const TextStyle(
                          color: Color(0xFF20262C),
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${resolutionCase.productName} · '
                        '${resolutionCase.openQuantity} '
                        '${resolutionCase.openQuantity == 1 ? 'unidad' : 'unidades'} '
                        '${resolutionCase.kind.label.toLowerCase()}',
                        style: const TextStyle(
                          color: Color(0xFF68747D),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onCancel,
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFD8DEE3)),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 14, 22, 8),
            child: Text(
              'Selecciona cómo continuará este caso. La recepción física ya '
              'está registrada y no será modificada por esta elección.',
              style: TextStyle(
                color: Color(0xFF52606A),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          _ResolutionOutcomeOption(
            icon: Icons.request_quote_outlined,
            title: 'Nota de crédito del proveedor',
            description:
                'Prepara el documento que corrige cuentas por pagar e IVA, '
                'sin inventar entrada de stock.',
            onTap: () =>
                onSelected(PurchaseReceiptResolutionOutcome.creditNote),
          ),
          _ResolutionOutcomeOption(
            icon: Icons.local_shipping_outlined,
            title: 'Entrega posterior',
            description:
                'Abre una nueva recepción y permite asignar la entrega a esta '
                'diferencia por línea.',
            onTap: () =>
                onSelected(PurchaseReceiptResolutionOutcome.laterDelivery),
          ),
          _ResolutionOutcomeOption(
            icon: Icons.report_gmailerrorred_outlined,
            title: 'Pérdida documentada',
            description:
                'Reconoce la pérdida contable. No mueve stock porque la '
                'mercadería nunca fue aceptada.',
            warning: true,
            onTap: () =>
                onSelected(PurchaseReceiptResolutionOutcome.documentedLoss),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Cancelar'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolutionOutcomeOption extends StatelessWidget {
  const _ResolutionOutcomeOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        hoverColor: const Color(0xFFF4F7F8),
        focusColor: const Color(0xFFEAF1F3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  icon,
                  size: 20,
                  color: warning
                      ? const Color(0xFF996719)
                      : const Color(0xFF235466),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF20262C),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF68747D),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.chevron_right,
                  size: 19,
                  color: Color(0xFF8A969E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
