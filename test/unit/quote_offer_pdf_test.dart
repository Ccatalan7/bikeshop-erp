// The offer PDF has one drawing (`buildQuoteOfferPdf` in the shared core):
// the HTML store reads the quote with its link (`get_public_customer_quote_v1`)
// and the ERP with `customer_quote_offer_document_v1`, both the projection
// the customer sees (20261103050000). These are the words it states.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/public_store/documents/quote_offer_pdf.dart';

Map<String, Object?> _projection({
  String status = 'offered',
  String offerStatus = 'sent',
  Object? storefront = const {
    'schemaVersion': 1,
    'displayName': 'Viñabike',
    'legalName': 'NEWEN SpA',
    'tagline': 'Repuestos, accesorios y taller de bicicletas en Viña del Mar.',
    'supportEmail': 'contacto@example.invalid',
    'supportPhone': '+56 9 0000 0000',
    'storeUrl': 'https://www.vinabike.cl/',
  },
  bool withOffer = true,
  String? notes = 'Si quieres, te lo dejamos montado en el taller.',
}) =>
    {
      'quote': {
        'number': 'COT-26-00012',
        'status': status,
        'customerName': 'Pía Contreras',
        'expiresAt': '2026-11-06T15:00:00+00:00',
        'acceptedAt': status == 'accepted' ? '2026-11-04T14:20:00+00:00' : null,
        'expiredAt': status == 'expired' ? '2026-11-06T15:00:00+00:00' : null,
      },
      'storefront': storefront,
      'offer': withOffer
          ? {
              'number': 2,
              'status': offerStatus,
              'sentAt': '2026-11-03T15:00:00+00:00',
              'validUntil': '2026-11-06T15:00:00+00:00',
              'subtotal': 90756,
              'taxAmount': 17244,
              'total': 108000,
              'notes': notes,
              'lines': [
                {
                  'name': 'Cámara 29 válvula presta',
                  'sku': 'CAM-29-FV',
                  'quantityRequested': 2,
                  'quantity': 2,
                  'availability': 'in_stock',
                  'unitPrice': 6000,
                  'lineTotal': 12000,
                },
                {
                  'name': 'Neumático Maxxis Rekon 29 x 2.40',
                  'quantityRequested': 3,
                  'quantity': 2,
                  'availability': 'on_order',
                  'unitPrice': 48000,
                  'lineTotal': 96000,
                  'leadDaysMin': 3,
                  'leadDaysMax': 5,
                  'note': 'Del lote que llega el jueves.',
                },
                {
                  'name': 'Bomba de piso con manómetro',
                  'quantityRequested': 1,
                  'quantity': 0,
                  'availability': 'unavailable',
                  'note': 'El proveedor no la tiene.',
                },
              ],
            }
          : null,
    };

void main() {
  test('a sent offer reads with the letterhead and the page\'s words', () {
    final quote = QuoteOfferPdfInput.fromPublicQuote(_projection())!;

    expect(quote.storeName, 'Viñabike');
    expect(quote.legalName, 'NEWEN SpA');
    expect(quote.storeOrigin, 'https://www.vinabike.cl');
    expect(quote.storeHost, 'vinabike.cl');
    expect(quote.quoteNumber, 'COT-26-00012');
    expect(quote.offerNumber, 2);
    expect(quote.customerName, 'Pía Contreras');
    expect(quote.statusLabel, 'Vigente');
    expect(quote.fileName, 'cotizacion_COT-26-00012.pdf');
    expect(quote.total, 108000);
    expect([
      for (final line in quote.lines) line.availabilityLabel
    ], [
      'En stock',
      'A pedido · 2 de 3 · llega en 3 a 5 días hábiles',
      'No disponible',
    ]);
    expect([
      for (final line in quote.lines) line.isOffered
    ], [
      true,
      true,
      false,
    ]);
    expect(
      quote.contactLine,
      '¿Dudas? Escríbenos a contacto@example.invalid o al +56 9 0000 0000.',
    );
  });

  test('what comes next follows the quote', () {
    String next(String status, {String offerStatus = 'sent'}) =>
        QuoteOfferPdfInput.fromPublicQuote(
          _projection(status: status, offerStatus: offerStatus),
        )!
            .nextStep;

    expect(
      next('offered'),
      'Ábrela con el enlace que te mandamos o en vinabike.cl › Mi cuenta › '
      'Cotizaciones y toca «Aceptar oferta»: eliges retiro o despacho y '
      'pagas. Lo que viene a pedido lo pedimos al tiro y te avisamos cuando '
      'llegue.',
    );
    expect(next('accepted', offerStatus: 'accepted'),
        startsWith('Aceptaste esta oferta el 04/11/2026.'));
    expect(
        next('expired'),
        'Esta oferta venció el 06/11/2026. Escríbenos y '
        'la renovamos.');
    expect(next('confirming', offerStatus: 'superseded'),
        startsWith('Esta es la oferta anterior'));
    expect(
      QuoteOfferPdfInput.fromPublicQuote(
        _projection(status: 'confirming', offerStatus: 'superseded'),
      )!
          .statusLabel,
      'Oferta anterior',
    );
  });

  test(
      'without the identity the store is still named, and no web address '
      'is made up', () {
    final quote =
        QuoteOfferPdfInput.fromPublicQuote(_projection(storefront: null))!;

    expect(quote.storeName, 'Tienda');
    expect(quote.storeOrigin, isNull);
    expect(quote.contactLine, isNull);
    expect(
        quote.nextStep, contains('en la tienda, en Mi cuenta › Cotizaciones'));
  });

  test('no sent offer, no document', () {
    expect(QuoteOfferPdfInput.fromPublicQuote(_projection(withOffer: false)),
        isNull);
    expect(QuoteOfferPdfInput.fromPublicQuote(null), isNull);
    expect(QuoteOfferPdfInput.fromPublicQuote('{"quote":{}}'), isNull);
  });

  // Set QUOTE_PDF_OUT=<dir> to keep the drawn files for a visual check.
  test('the offer is drawn on one page', () async {
    final regular = File('assets/fonts/Barlow-Regular.ttf').readAsBytesSync();
    final bold = File('assets/fonts/Barlow-Bold.ttf').readAsBytesSync();
    final out = Platform.environment['QUOTE_PDF_OUT'];
    for (final status in ['offered', 'accepted', 'expired']) {
      final bytes = await buildQuoteOfferPdf(
        QuoteOfferPdfInput.fromPublicQuote(_projection(status: status))!,
        regularFont: ByteData.sublistView(regular),
        boldFont: ByteData.sublistView(bold),
      );
      if (out != null) {
        File('$out/cotizacion-$status.pdf').writeAsBytesSync(bytes);
      }
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });
}
