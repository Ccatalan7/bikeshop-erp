import 'package:flutter/material.dart';

import '../modules/purchases/models/purchase_invoice.dart';
import '../modules/purchases/models/purchase_receipt.dart';
import '../modules/purchases/pages/purchase_receiving_page.dart';
import '../shared/themes/app_theme.dart';

/// Visual-only purchase receiving harness.
///
/// Run with:
/// bash scripts/dev/flutter.sh run -d macos \
///   -t lib/dev/purchase_receiving_preview.dart
///
/// Every loader and command is replaced with an in-memory fixture. This
/// entrypoint does not initialize Supabase and cannot post inventory,
/// accounting, payment, or purchase document changes.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PurchaseReceivingPreviewApp());
}

class PurchaseReceivingPreviewApp extends StatelessWidget {
  const PurchaseReceivingPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Preview · Recepción de compra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const PurchaseReceivingPreviewShell(),
    );
  }
}

enum PurchaseReceivingPreviewScenario {
  newReceipt,
  partialReceipt,
  completeReceipt,
}

extension on PurchaseReceivingPreviewScenario {
  String get label => switch (this) {
        PurchaseReceivingPreviewScenario.newReceipt => 'Primera recepción',
        PurchaseReceivingPreviewScenario.partialReceipt =>
          'Recepción previa parcial',
        PurchaseReceivingPreviewScenario.completeReceipt =>
          'Recepción ya completa',
      };
}

class PurchaseReceivingPreviewShell extends StatefulWidget {
  const PurchaseReceivingPreviewShell({super.key});

  @override
  State<PurchaseReceivingPreviewShell> createState() =>
      _PurchaseReceivingPreviewShellState();
}

class _PurchaseReceivingPreviewShellState
    extends State<PurchaseReceivingPreviewShell> {
  PurchaseReceivingPreviewScenario _scenario =
      PurchaseReceivingPreviewScenario.newReceipt;
  int _receiptSequence = 1;

  PurchaseInvoice get _invoice => PurchaseInvoice(
        id: 'preview-invoice-51611',
        tenantId: 'preview-tenant',
        invoiceNumber: '51611',
        supplierId: 'preview-supplier',
        supplierName: 'Comercial Ciclo',
        supplierRut: '76.000.000-0',
        date: DateTime(2026, 7, 22),
        status: PurchaseInvoiceStatus.paid,
        subtotal: 50385,
        ivaAmount: 9573,
        total: 59958,
        paidAmount: 59958,
        balance: 0,
        prepaymentModel: true,
        items: [
          PurchaseInvoiceItem(
            productId: 'preview-product-1',
            productName: 'Cámara 10TEN Butyl 26',
            productSku: 'PREVIEW-001',
            quantity: 10,
            unitCost: 2090,
          ),
          PurchaseInvoiceItem(
            productId: 'preview-product-2',
            productName: 'Cámara Maxxis Welter Weight 29',
            productSku: 'PREVIEW-002',
            quantity: 1,
            unitCost: 13990,
          ),
          PurchaseInvoiceItem(
            productId: 'preview-product-3',
            productName: 'Cámara RideXC Butyl 29',
            productSku: 'PREVIEW-003',
            quantity: 1,
            unitCost: 12990,
          ),
          PurchaseInvoiceItem(
            productId: 'preview-product-4',
            productName: 'Cadena de transmisión 9 velocidades',
            productSku: 'PREVIEW-004',
            quantity: 1,
            unitCost: 6990,
          ),
        ],
      );

  Map<int, int> get _previouslyReceived => switch (_scenario) {
        PurchaseReceivingPreviewScenario.newReceipt => const {},
        PurchaseReceivingPreviewScenario.partialReceipt => const {
            0: 4,
            2: 1,
          },
        PurchaseReceivingPreviewScenario.completeReceipt => const {
            0: 10,
            1: 1,
            2: 1,
            3: 1,
          },
      };

  Future<Map<int, int>> _loadPrevious(String invoiceId) async {
    return Map<int, int>.from(_previouslyReceived);
  }

  Future<Map<String, String>> _loadProductImages(
    Iterable<String> productIds,
  ) async {
    const images = {
      'preview-product-1':
          'asset:assets/images/campaigns/products/10ten-butyl-26-cutout.png',
      'preview-product-2':
          'asset:assets/images/campaigns/products/maxxis-welter-weight-29-cutout.png',
      'preview-product-3':
          'asset:assets/images/campaigns/products/ridexc-butyl-29-cutout.png',
      'preview-product-4': 'asset:assets/images/chain_icon.png',
    };
    return {
      for (final id in productIds)
        if (images.containsKey(id)) id: images[id]!,
    };
  }

  Future<PurchaseReceiptResult> _simulateReceipt({
    required String invoiceId,
    required List<PurchaseReceiptLineDraft> lines,
    required DateTime receivedAt,
    required String idempotencyKey,
    String? deliveryReference,
    String? locationLabel,
    String? notes,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final sequence = _receiptSequence++;
    return PurchaseReceiptResult(
      receiptId: 'preview-receipt-$sequence',
      operationId: 'preview-operation-$sequence',
      receiptNumber: 'PREVIEW-${sequence.toString().padLeft(3, '0')}',
      replayed: false,
    );
  }

  Future<void> _handleCompleted(PurchaseReceiptResult result) async {
    setState(
      () => _scenario = PurchaseReceivingPreviewScenario.completeReceipt,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.receiptNumber} simulada. No se guardó ningún dato.',
        ),
      ),
    );
  }

  void _handleCancel() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Preview local: esta acción no navega ni modifica datos.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          _PreviewSafetyBar(
            scenario: _scenario,
            onScenarioChanged: (scenario) {
              if (scenario == null) return;
              setState(() => _scenario = scenario);
            },
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 300,
                  child: _PreviewInvoiceMaster(
                    invoice: _invoice,
                    scenario: _scenario,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: PurchaseReceivingWorkspace(
                    key: ValueKey(_scenario),
                    invoice: _invoice,
                    onCancel: _handleCancel,
                    onCompleted: _handleCompleted,
                    previousLoader: _loadPrevious,
                    productImageLoader: _loadProductImages,
                    receiptCreator: _simulateReceipt,
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

class _PreviewSafetyBar extends StatelessWidget {
  const _PreviewSafetyBar({
    required this.scenario,
    required this.onScenarioChanged,
  });

  final PurchaseReceivingPreviewScenario scenario;
  final ValueChanged<PurchaseReceivingPreviewScenario?> onScenarioChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'PREVIEW LOCAL',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Datos ficticios · sin conexión ni escrituras',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Escenario',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<PurchaseReceivingPreviewScenario>(
            value: scenario,
            isDense: true,
            underline: const SizedBox.shrink(),
            onChanged: onScenarioChanged,
            items: [
              for (final option in PurchaseReceivingPreviewScenario.values)
                DropdownMenuItem(
                  value: option,
                  child: Text(option.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewInvoiceMaster extends StatelessWidget {
  const _PreviewInvoiceMaster({
    required this.invoice,
    required this.scenario,
  });

  final PurchaseInvoice invoice;
  final PurchaseReceivingPreviewScenario scenario;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Facturas de compra',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Contexto simulado del split pane',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          _PreviewInvoiceRow(
            invoiceNumber: invoice.invoiceNumber,
            supplierName: invoice.supplierName ?? 'Sin proveedor',
            total: '\$59.958',
            status: scenario == PurchaseReceivingPreviewScenario.completeReceipt
                ? 'PAGADA · RECIBIDA'
                : scenario == PurchaseReceivingPreviewScenario.partialReceipt
                    ? 'PAGADA · PARCIAL'
                    : 'PAGADA',
            selected: true,
          ),
          const _PreviewInvoiceRow(
            invoiceNumber: 'FC-00026',
            supplierName: 'TeknoBike',
            total: '\$92.356',
            status: 'BORRADOR',
          ),
          const _PreviewInvoiceRow(
            invoiceNumber: '545',
            supplierName: 'Garozzo',
            total: '\$12.000',
            status: 'RECIBIDA',
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Maximiza la ventana para revisar la tabla con su densidad de '
              'escritorio.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewInvoiceRow extends StatelessWidget {
  const _PreviewInvoiceRow({
    required this.invoiceNumber,
    required this.supplierName,
    required this.total,
    required this.status,
    this.selected = false,
  });

  final String invoiceNumber;
  final String supplierName;
  final String total;
  final String status;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? theme.colorScheme.surfaceContainerHigh : null,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invoiceNumber,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                status,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            supplierName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              total,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
