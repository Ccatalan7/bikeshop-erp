// The delivery and warranty document has one drawing
// (`buildDeliveryWarrantyPdf` in the shared core): the ERP reads it with
// `ensure_job_delivery_document_v1` and the customer's account with
// `list_my_job_delivery_documents_v1`, both the projection of
// `mechanic_job_delivery_documents` (20261104200000…220000). These are the
// words it states.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/public_store/documents/delivery_warranty_pdf.dart';
import 'package:vinabike_public_core/public_store/documents/store_document_style.dart';
import 'package:vinabike_public_core/public_store/models/storefront_logo_source.dart';

Map<String, Object?> _projection({
  Object? storefront = const {
    'schemaVersion': 1,
    'displayName': 'Viñabike',
    'legalName': 'NEWEN SpA',
    'tagline': 'Repuestos, accesorios y taller de bicicletas en Viña del Mar.',
    'supportEmail': 'contacto@example.invalid',
    'supportPhone': '+56 9 0000 0000',
    'storeUrl': 'https://www.vinabike.cl/',
  },
  List<Map<String, Object?>>? bikes,
  List<Map<String, Object?>>? lines,
  String? clientRequest = 'Revisar frenos + cambio de cadena',
  int serviceDays = 14,
}) =>
    {
      'id': 'doc-1',
      'job_id': 'job-1',
      'job_number': 'PG-26-00412',
      'delivered_at': '2026-11-04T19:30:00+00:00',
      'service_warranty_days': serviceDays,
      'service_warranty_expires_at': '2026-11-18T19:30:00+00:00',
      'service_warranty_days_remaining': 14,
      'parts_warranty_months': 2,
      'parts_warranty_expires_at': '2027-01-04T19:30:00+00:00',
      'parts_warranty_days_remaining': 61,
      'invoice_id': null,
      'storefront': storefront,
      'snapshot': {
        'job_number': 'PG-26-00412',
        'customer': {'name': 'Pía Contreras'},
        'client_request': clientRequest,
        'diagnosis': 'Pastillas gastadas y cadena estirada.',
        'work_performed': null,
        'subject_notes': null,
        'bikes': bikes ??
            [
              {
                'job_bike_id': 'jb-1',
                'brand': 'Trek',
                'model': 'Marlin 7',
                'year': 2022,
                'color': 'Negra',
                'serial_number': 'WTU123',
                'work_requested': null,
                'work_performed': null,
              },
            ],
        'lines': lines ??
            [
              {
                'kind': 'service',
                'name': 'Mantención completa',
                'quantity': 1,
                'job_bike_id': 'jb-1'
              },
              {
                'kind': 'part',
                'name': 'Pastillas Shimano B01S',
                'quantity': 2,
                'job_bike_id': 'jb-1'
              },
              {
                'kind': 'other',
                'name': 'Limpieza de transmisión',
                'quantity': 1,
                'job_bike_id': null
              },
              {
                'kind': 'part',
                'name': '   ',
                'quantity': 1,
                'job_bike_id': null
              },
            ],
      },
    };

void main() {
  test('a delivery reads with the letterhead, both warranties and the job', () {
    final document = DeliveryWarrantyPdfInput.fromProjection(_projection())!;

    expect(document.storeName, 'Viñabike');
    expect(document.storeOrigin, 'https://www.vinabike.cl');
    expect(document.storeHost, 'vinabike.cl');
    expect(document.jobNumber, 'PG-26-00412');
    expect(document.fileName, 'comprobante_entrega_PG-26-00412.pdf');
    expect(document.customerName, 'Pía Contreras');
    expect(document.serviceWarrantyLabel, '14 días');
    expect(document.partsWarrantyLabel, '2 meses');
    expect(document.requestSummary, 'Revisar frenos + cambio de cadena');
    expect(document.diagnosis, 'Pastillas gastadas y cadena estirada.');
    expect(document.bikes.single.title, 'Trek Marlin 7 2022');
    expect(document.bikes.single.detail, 'Negra · N° de serie WTU123');
    // A line without a name is not drawn.
    expect([
      for (final line in document.lines) line.name
    ], [
      'Mantención completa',
      'Pastillas Shimano B01S',
      'Limpieza de transmisión',
    ]);
    expect([for (final line in document.lines) line.quantityLabel],
        [null, '× 2', null]);
    expect(document.hasParts, isTrue);
    expect(
      document.contactLine,
      'contacto@example.invalid · +56 9 0000 0000',
    );
    expect(document.thanksLine, 'Gracias por confiar en Viñabike.');
  });

  test('the instructions are three short lines and the legal one', () {
    final document = DeliveryWarrantyPdfInput.fromProjection(_projection())!;

    expect(document.instructions, hasLength(3));
    expect(document.instructions.first,
        'Cubre la mano de obra y los repuestos instalados en este servicio.');
    expect(DeliveryWarrantyPdfInput.legalLine,
        'Sin perjuicio de la garantía legal (Ley 19.496).');
  });

  test('the QR goes only to a customer without an account', () {
    final url =
        customerPortalClaimUrl('https://www.vinabike.cl/', 'abc_DEF-123');
    expect(url, 'https://www.vinabike.cl/cuenta/vincular#c=abc_DEF-123');

    final withoutAccount =
        DeliveryWarrantyPdfInput.fromProjection(_projection(), claimUrl: url)!;
    expect(withoutAccount.claimUrl, url);
    expect(DeliveryWarrantyPdfInput.claimTitle, 'Crea tu cuenta');

    final withAccount = DeliveryWarrantyPdfInput.fromProjection(
      _projection(),
      hasAccount: true,
    )!;
    expect(withAccount.claimUrl, isNull);
    expect(withAccount.accountLine,
        'Este comprobante también está en tu cuenta en vinabike.cl.');
  });

  test('several bikes list their own work; loose lines go last', () {
    final document = DeliveryWarrantyPdfInput.fromProjection(
      _projection(
        bikes: [
          {'job_bike_id': 'jb-1', 'brand': 'Trek', 'model': 'Marlin 7'},
          {
            'job_bike_id': 'jb-2',
            'brand': 'Oxford',
            'model': 'Merak',
            'work_requested': 'Parche'
          },
        ],
        lines: [
          {
            'kind': 'service',
            'name': 'Mantención',
            'quantity': 1,
            'job_bike_id': 'jb-1'
          },
          {
            'kind': 'service',
            'name': 'Parche cámara',
            'quantity': 1,
            'job_bike_id': 'jb-2'
          },
          {
            'kind': 'other',
            'name': 'Lavado',
            'quantity': 1,
            'job_bike_id': null
          },
        ],
        clientRequest: null,
      ),
    )!;

    expect([for (final group in document.groups) group.bike?.title],
        ['Trek Marlin 7', 'Oxford Merak', null]);
    expect([
      for (final group in document.groups)
        [for (final line in group.lines) line.name]
    ], [
      ['Mantención'],
      ['Parche cámara'],
      ['Lavado'],
    ]);
    // Without a job-level request, each bike's says what was asked.
    expect(document.requestSummary, 'Parche');
  });

  test('no number, no delivery or no warranty dates, no document', () {
    expect(DeliveryWarrantyPdfInput.fromProjection(null), isNull);
    expect(
        DeliveryWarrantyPdfInput.fromProjection({'job_number': 'X'}), isNull);
    final noDate = Map<String, Object?>.of(_projection())
      ..remove('delivered_at');
    expect(DeliveryWarrantyPdfInput.fromProjection(noDate), isNull);
  });

  test(
      'without the identity the store is still named, and no web address is '
      'made up', () {
    final document =
        DeliveryWarrantyPdfInput.fromProjection(_projection(storefront: null))!;
    expect(document.storeName, 'Tienda');
    expect(document.storeOrigin, isNull);
    expect(document.accountLine, 'Este comprobante también está en tu cuenta.');
  });

  test('a job without parts says nothing of a parts warranty', () {
    final withParts = DeliveryWarrantyPdfInput.fromProjection(_projection())!;
    expect(withParts.showsPartsWarranty, isTrue);

    final onlyService = DeliveryWarrantyPdfInput.fromProjection(
      _projection(
        lines: [
          {'kind': 'service', 'name': 'Regulación de frenos', 'quantity': 2},
        ],
      ),
    )!;
    expect(onlyService.showsPartsWarranty, isFalse);
    expect(onlyService.instructions.first,
        'Cubre la mano de obra de este servicio.');
  });

  test('a shop without service warranty says so', () {
    final document =
        DeliveryWarrantyPdfInput.fromProjection(_projection(serviceDays: 0))!;
    expect(document.serviceWarrantyLabel, 'Sin garantía');
  });

  test('the letterhead takes the store logo by the site\'s rule', () {
    // The canonical store, without a logo of its own on the site: the
    // bundled one, as the store draws it.
    expect(
      storeDocumentLogoSource(tenantId: VinabikeCanonicalTenant.id),
      'assets/$storefrontBundledLogoAsset',
    );
    // A logo on the site wins.
    expect(
      storeDocumentLogoSource(
        identityLogoUrl: 'https://cdn.example.invalid/logo.png',
        tenantId: VinabikeCanonicalTenant.id,
      ),
      'https://cdn.example.invalid/logo.png',
    );
    // Another store without one: its name in letters.
    expect(storeDocumentLogoSource(tenantId: 'otro'), isNull);
    // Bytes that are not an image never break the document.
    expect(storeDocumentLogoImage(Uint8List.fromList([1, 2, 3])), isNull);
    expect(
      storeDocumentLogoImage(
        File('assets/images/vinabike_logo.webp').readAsBytesSync(),
      ),
      isNotNull,
    );
  });

  // Set DELIVERY_PDF_OUT=<dir> to keep the drawn files for a visual check.
  test('the document is drawn, with and without the QR', () async {
    final regular = File('assets/fonts/Barlow-Regular.ttf').readAsBytesSync();
    final bold = File('assets/fonts/Barlow-Bold.ttf').readAsBytesSync();
    final logo = File('assets/images/vinabike_logo.webp').readAsBytesSync();
    final out = Platform.environment['DELIVERY_PDF_OUT'];
    final cases = {
      'con-qr': DeliveryWarrantyPdfInput.fromProjection(
        _projection(),
        claimUrl: customerPortalClaimUrl(
          'https://vinabike.cl',
          'q1w2e3r4t5y6u7i8o9p0a1s2d3f4g5h6j7k8l9z0x1c',
        ),
      )!,
      'con-cuenta': DeliveryWarrantyPdfInput.fromProjection(
        _projection(),
        hasAccount: true,
      )!,
      'varias-bicis': DeliveryWarrantyPdfInput.fromProjection(
        _projection(
          bikes: [
            {'job_bike_id': 'jb-1', 'brand': 'Trek', 'model': 'Marlin 7'},
            {'job_bike_id': 'jb-2', 'brand': 'Oxford', 'model': 'Merak'},
          ],
          lines: [
            {
              'kind': 'service',
              'name': 'Mantención',
              'quantity': 1,
              'job_bike_id': 'jb-1'
            },
            {
              'kind': 'part',
              'name': 'Cadena KMC X11',
              'quantity': 1,
              'job_bike_id': 'jb-1'
            },
            {
              'kind': 'service',
              'name': 'Parche cámara',
              'quantity': 1,
              'job_bike_id': 'jb-2'
            },
          ],
        ),
      )!,
    };
    for (final entry in cases.entries) {
      final bytes = await buildDeliveryWarrantyPdf(
        entry.value,
        regularFont: ByteData.sublistView(regular),
        boldFont: ByteData.sublistView(bold),
        logo: logo,
      );
      if (out != null) {
        File('$out/comprobante-${entry.key}.pdf').writeAsBytesSync(bytes);
      }
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });
}
