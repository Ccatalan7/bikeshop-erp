import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/settings/models/company_profile.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/services/online_order_shipping_label_pdf.dart';

/// The shipping label of an online order (2026-10-13): what each line says
/// and that it builds on both papers. Synthetic data only.
void main() {
  final shipDate = DateTime(2026, 10, 13, 12);

  test('the label reads the order and the company in carrier words', () {
    final data = ShippingLabelData.fromOrder(
      _order(),
      company: _company(),
      recipientRut: null,
      shipDate: shipDate,
    );

    expect(data.recipientName, 'Cliente de Prueba');
    expect(data.street, 'Calle Sintética 123, Depto 4');
    expect(data.comuna, 'VIÑA DEL MAR');
    expect(data.regionLine, 'Región de Valparaíso · CP 2520000');
    expect(data.phone, '+56 9 0000 0000');
    // No RUT on the customer: the label leaves the line to write by hand.
    expect(data.recipientRut, isNull);
    expect(data.instructions, 'Tocar el timbre dos veces.');
    expect(
      data.senderTitle,
      'Bicis de Prueba · Empresa de Prueba SpA · RUT 76.000.000-0',
    );
    expect(
      data.senderAddress,
      'Calle Falsa 1, Viña del Mar · Región de Valparaíso · CP 2520000',
    );
    expect(data.senderContact, '+56 9 1111 1111 · hola@example.invalid');
    expect(data.website, 'example.invalid');
    expect(data.contents, '1 × Adaptador de prueba 28.6 mm');
    // What the box holds, not what the customer paid for delivery.
    expect(data.declaredValue, 11000);
  });

  test('a known RUT is printed instead of the blank line', () {
    final data = ShippingLabelData.fromOrder(
      _order(),
      company: _company(),
      recipientRut: '111111111',
      shipDate: shipDate,
    );
    expect(data.recipientRut, '11.111.111-1');
  });

  test('the label builds on 10 × 15 cm and on letter, one per package',
      () async {
    final fonts = ShippingLabelFonts(
      regular: _font('Barlow-Regular'),
      medium: _font('Barlow-Medium'),
      semiBold: _font('Barlow-SemiBold'),
      bold: _font('Barlow-Bold'),
      extraBold: _font('Barlow-ExtraBold'),
    );
    final data = ShippingLabelData.fromOrder(
      _order(),
      company: _company(),
      recipientRut: null,
      shipDate: shipDate,
    );

    for (final paper in ShippingLabelPaper.values) {
      final bytes = await buildShippingLabelPdf(
        data,
        packages: 3,
        paper: paper,
        fonts: fonts,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: paper.name);
      final shots = Platform.environment['SHIPPING_LABEL_PDF'];
      if (shots != null) {
        File('$shots/etiqueta-${paper.name}.pdf').writeAsBytesSync(bytes);
      }
    }
  });
}

ByteData _font(String name) {
  final bytes = File('assets/fonts/$name.ttf').readAsBytesSync();
  return ByteData.sublistView(bytes);
}

CompanyProfile _company() => const CompanyProfile(
      name: 'Bicis de Prueba',
      legalName: 'Empresa de Prueba SpA',
      fantasyName: 'Bicis de Prueba',
      taxId: '760000000',
      businessActivity: '',
      address: 'Calle Falsa 1',
      comuna: 'Viña del Mar',
      city: 'Viña del Mar',
      region: 'Valparaíso',
      postalCode: '2520000',
      country: 'Chile',
      phone: '+56911111111',
      whatsappPhone: '',
      whatsappApiPhone: '',
      supportPhone: '',
      email: 'hola@example.invalid',
      billingEmail: '',
      publicEmail: '',
      websiteUrl: 'https://example.invalid/',
    );

OnlineOrder _order() {
  final createdAt = DateTime(2026, 10, 12, 15, 52);
  return OnlineOrder(
    id: '9e400000-0000-4000-8000-000000000031',
    tenantId: '9e400000-0000-4000-8000-000000000001',
    orderNumber: 'WEB-26-00031',
    customerEmail: 'cliente@example.invalid',
    customerName: 'Cliente de Prueba',
    customerPhone: '+56900000000',
    deliveryType: 'shipping',
    shippingAddressLine1: 'Calle Sintética 123',
    shippingAddressLine2: 'Depto 4',
    shippingCity: 'Viña del Mar',
    shippingState: 'Región de Valparaíso',
    shippingPostalCode: '2520000',
    shippingCountry: 'Chile',
    subtotal: 9244,
    taxAmount: 1756,
    shippingCost: 6990,
    discountAmount: 0,
    total: 17990,
    status: 'confirmed',
    paymentStatus: 'paid',
    paymentMethod: 'mercadopago',
    customerNotes: 'Tocar el timbre dos veces.',
    createdAt: createdAt,
    updatedAt: createdAt,
    items: [
      OnlineOrderItem(
        id: 'item-1',
        orderId: '9e400000-0000-4000-8000-000000000031',
        productName: 'Adaptador de prueba 28.6 mm',
        productSku: 'PR0001',
        quantity: 1,
        unitPrice: 11000,
        subtotal: 11000,
        createdAt: createdAt,
      ),
    ],
  );
}
