import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:vinabike_public_core/public_store/documents/order_summary_pdf.dart';

import '../../modules/website/models/website_models.dart';

/// The customer-facing order summary, drawn by the shared core
/// ([buildOrderSummaryPdf]) so the HTML store's PDF is this same document.
/// It never claims fiscal validity: «No acredita pago».
Future<Uint8List> buildOrderPdfBytes(OnlineOrder order) async {
  final regularFont = await rootBundle.load('assets/fonts/Barlow-Regular.ttf');
  final boldFont = await rootBundle.load('assets/fonts/Barlow-Bold.ttf');
  return buildOrderSummaryPdf(
    orderSummaryInputOf(order),
    regularFont: regularFont,
    boldFont: boldFont,
  );
}

/// The ERP's order as the summary states it, with the storefront identity
/// frozen with the order (`order.storefrontIdentity.displayName`).
OrderSummaryPdfInput orderSummaryInputOf(OnlineOrder order) =>
    OrderSummaryPdfInput(
      storeName: order.storefrontIdentity.displayName,
      tagline: order.storefrontIdentity.tagline,
      orderNumber: order.orderNumber,
      createdAt: order.createdAt,
      statusLabel: order.statusDisplayName,
      paymentStatusLabel: order.paymentStatusDisplayName,
      deliveryLabel: order.deliveryDisplayName,
      customerRows: _customerRows(order),
      lines: [
        for (final item in order.items)
          OrderSummaryLine(
            name: item.productName,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            subtotal: item.subtotal,
            taxRate: item.taxRate,
          ),
      ],
      subtotal: order.subtotal,
      taxAmount: order.taxAmount,
      shippingCost: order.shippingCost,
      discountAmount: order.discountAmount,
      total: order.total,
    );

Future<void> downloadOrderPdf(OnlineOrder order) async {
  final bytes = await buildOrderPdfBytes(order);
  final fileName = 'pedido_${order.orderNumber}.pdf';

  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar resumen del pedido',
      fileName: fileName,
      allowedExtensions: const ['pdf'],
      type: FileType.custom,
    );

    if (outputFile != null) {
      await File(outputFile).writeAsBytes(bytes);
    }
    return;
  }

  await Printing.sharePdf(bytes: bytes, filename: fileName);
}

List<MapEntry<String, String>> _customerRows(OnlineOrder order) {
  final rows = <MapEntry<String, String>>[];
  void add(String label, String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) rows.add(MapEntry(label, normalized));
  }

  add('Nombre', order.customerName);
  add('Email', order.customerEmail);
  add('Teléfono', order.customerPhone);
  final hasAddress = [
    order.customerAddress,
    order.shippingAddressLine1,
    order.shippingAddressLine2,
    order.shippingCity,
    order.shippingState,
    order.shippingPostalCode,
  ].any((part) => part?.trim().isNotEmpty == true);
  if (hasAddress) add('Dirección', order.shippingAddressDisplay);
  return rows;
}
