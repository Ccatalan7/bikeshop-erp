import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/shop_time.dart';
import '../models/online_order_shipment.dart';
import '../models/website_models.dart';
import '../services/online_order_shipment_service.dart';
import 'online_order_sheet.dart';
import 'shipment_expense_fields.dart';

/// The order's shipment in its sheet: with whom it left, the code to follow
/// it, what the carrier charged against what the customer paid for delivery
/// and the expense it became (or the button to register it), and the
/// receipt it was registered with. An order shipped before receipts
/// existed shows the carrier and code it was given by hand.
class OnlineOrderShipmentSection extends StatefulWidget {
  const OnlineOrderShipmentSection({
    super.key,
    required this.order,
    this.service,
  });

  final OnlineOrder order;
  final OnlineOrderShipmentReader? service;

  @override
  State<OnlineOrderShipmentSection> createState() =>
      _OnlineOrderShipmentSectionState();
}

class _OnlineOrderShipmentSectionState
    extends State<OnlineOrderShipmentSection> {
  late OnlineOrderShipmentReader _service;
  late Future<List<OnlineOrderShipment>> _shipments;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? OnlineOrderShipmentService();
    _load();
  }

  @override
  void didUpdateWidget(covariant OnlineOrderShipmentSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != widget.order.id ||
        oldWidget.order.version != widget.order.version ||
        oldWidget.service != widget.service) {
      _service = widget.service ?? OnlineOrderShipmentService();
      _load();
    }
  }

  void _load() {
    _shipments = _service.loadForOrder(widget.order.id);
  }

  void _reload() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OnlineOrderShipment>>(
      future: _shipments,
      builder: (context, snapshot) {
        final shipment = snapshot.data?.firstOrNull;
        final order = widget.order;
        final carrier =
            shipment?.carrier ?? order.shippingCarrier?.trim() ?? '';
        final tracking =
            shipment?.trackingNumber ?? order.trackingNumber?.trim() ?? '';
        if (carrier.isEmpty && tracking.isEmpty) {
          return const SizedBox.shrink();
        }
        return _ShipmentCard(
          order: order,
          shipment: shipment,
          carrier: carrier,
          tracking: tracking,
          trackingUrl: shipment?.trackingUrl ?? order.trackingUrl,
          service: _service,
          onChanged: _reload,
        );
      },
    );
  }
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({
    required this.order,
    required this.shipment,
    required this.carrier,
    required this.tracking,
    required this.trackingUrl,
    required this.service,
    required this.onChanged,
  });

  final OnlineOrder order;
  final OnlineOrderShipment? shipment;
  final String carrier;
  final String tracking;
  final String? trackingUrl;
  final OnlineOrderShipmentReader service;
  final VoidCallback onChanged;

  Future<void> _registerExpense(BuildContext context) async {
    final registered = await showShipmentExpenseDialog(
      context,
      shipment: shipment!,
      service: service,
    );
    if (registered == null || !context.mounted) return;
    onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          registered.expenseNumber == null
              ? 'Gasto registrado.'
              : 'Gasto ${registered.expenseNumber} registrado.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final serviceName = shipment?.service?.trim() ?? '';
    final cost = shipment?.cost;
    final admittedAt = shipment?.admittedAt ?? order.shippedAt;
    final url = trackingUrl?.trim() ?? '';
    final receiptPath = shipment?.receiptPath;
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    // What the carrier charged, as an expense: open it, or register it.
    final expenseId = shipment?.expenseId;
    final Widget? expenseAction = expenseId != null
        ? OutlinedButton.icon(
            key: const ValueKey('shipment-open-expense'),
            onPressed: () => context.push('/accounting/expenses/$expenseId'),
            style: buttonStyle,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: Text(
              shipment?.expenseNumber == null
                  ? 'Ver gasto'
                  : 'Gasto ${shipment!.expenseNumber}',
            ),
          )
        : shipment != null && (cost ?? 0) > 0 && !order.isTest
            ? OutlinedButton.icon(
                key: const ValueKey('shipment-register-expense'),
                onPressed: () => _registerExpense(context),
                style: buttonStyle,
                icon: const Icon(Icons.add_card_outlined, size: 18),
                label: const Text('Registrar gasto'),
              )
            : null;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                carrier.isEmpty ? 'Transportista' : carrier,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (serviceName.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  serviceName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        if (tracking.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  tracking,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copiar número de seguimiento',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: tracking));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copiado: $tracking')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 19),
              ),
            ],
          ),
        ],
        if (admittedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            [
              'Entregado al transportista el '
                  '${ChileanUtils.formatDateTime(shopTime(admittedAt))}',
              if (shipment?.branch?.trim().isNotEmpty == true)
                shipment!.branch!.trim(),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
        if (cost != null) ...[
          const SizedBox(height: 4),
          Text(
            'Pagado al transportista ${ChileanUtils.formatCurrency(cost)}'
            '${order.shippingCost > 0 ? ' · cobrado al cliente ${ChileanUtils.formatCurrency(order.shippingCost)}' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
        if (url.startsWith('https://') || expenseAction != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (url.startsWith('https://'))
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ),
                  style: buttonStyle,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Seguir envío'),
                ),
              if (expenseAction != null) expenseAction,
            ],
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnlineOrderSectionLabel('Envío'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: roles.hairline),
          ),
          child: receiptPath == null
              ? details
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: 12),
                    _ReceiptThumbnail(path: receiptPath, service: service),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ReceiptThumbnail extends StatefulWidget {
  const _ReceiptThumbnail({required this.path, required this.service});

  final String path;
  final OnlineOrderShipmentReader service;

  @override
  State<_ReceiptThumbnail> createState() => _ReceiptThumbnailState();
}

class _ReceiptThumbnailState extends State<_ReceiptThumbnail> {
  late final Future<String?> _url = widget.service.receiptUrl(widget.path);

  bool get _isPdf => widget.path.toLowerCase().endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final placeholder = Icon(
      _isPdf ? Icons.picture_as_pdf_outlined : Icons.receipt_long_outlined,
      color: roles.faintForeground,
    );
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snapshot) {
        final url = snapshot.data;
        return Semantics(
          button: true,
          label: 'Ver la boleta del envío',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: url == null ? null : () => _open(context, url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 72,
                height: 96,
                color: theme.colorScheme.surfaceContainerHigh,
                alignment: Alignment.center,
                child: url == null || _isPdf
                    ? placeholder
                    : Image.network(
                        url,
                        width: 72,
                        height: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => placeholder,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _open(BuildContext context, String url) {
    if (_isPdf) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(dialogContext),
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
