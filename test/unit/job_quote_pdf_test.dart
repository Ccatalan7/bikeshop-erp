// The workshop quote the customer gets with the WhatsApp notice «Presupuesto
// listo» (20261107130000): one drawing in the shared core
// (`buildJobQuotePdf`), read by the HTML store with the notice's one-time
// code. These are the words it states.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/public_store/documents/job_quote_pdf.dart';

Map<String, Object?> _projection({
  num discount = 0,
  List<Map<String, Object?>>? lines,
  String? item = 'Trek Marlin 7',
}) =>
    {
      'job_id': 'job-1',
      'job_number': 'PG-00671',
      'valid_until': '2026-11-21T22:00:00+00:00',
      'issued_at': '2026-11-07T14:00:00+00:00',
      'customer': {'name': 'Camila Torres'},
      'item': item,
      'client_request': 'Cambia mal los cambios',
      'diagnosis': 'Cassette y cadena gastados.',
      'lines': lines ??
          [
            {
              'kind': 'service',
              'name': 'Cambio de cassette 11-46',
              'quantity': 1,
              'unit_price': 39990,
              'total': 39990,
            },
            {
              'kind': 'part',
              'name': 'Cadena 10 velocidades',
              'quantity': 1,
              'unit_price': 20000,
              'total': 20000,
            },
          ],
      'subtotal': 59990,
      'discount': discount,
      'total': 59990 - discount,
      'storefront': {
        'schemaVersion': 1,
        'displayName': 'Viñabike',
        'legalName': 'NEWEN SpA',
        'tagline':
            'Repuestos, accesorios y taller de bicicletas en Viña del Mar.',
        'supportEmail': 'contacto@example.invalid',
        'supportPhone': '+56 9 0000 0000',
        'storeUrl': 'https://www.vinabike.cl/',
      },
    };

void main() {
  test('a quote reads with the letterhead, the job and its lines', () {
    final quote = JobQuotePdfInput.fromProjection(_projection())!;
    expect(quote.storeName, 'Viñabike');
    expect(quote.storeOrigin, 'https://www.vinabike.cl');
    expect(quote.jobNumber, 'PG-00671');
    expect(quote.fileName, 'Presupuesto PG-00671.pdf');
    expect(quote.customerName, 'Camila Torres');
    expect(quote.itemLabel, 'Trek Marlin 7');
    expect(quote.clientRequest, 'Cambia mal los cambios');
    expect(quote.diagnosis, 'Cassette y cadena gastados.');
    expect([
      for (final line in quote.lines) '${line.kindLabel} ${line.name}'
    ], [
      'Servicio Cambio de cassette 11-46',
      'Repuesto Cadena 10 velocidades',
    ]);
    expect(quote.total, 59990);
    expect(quote.contactLine,
        '¿Dudas? Escríbenos a contacto@example.invalid o al +56 9 0000 0000.');
    expect(JobQuotePdfInput.howToApprove, contains('«Aprobar presupuesto»'));
  });

  test('a bike without a name says nothing more than the job number', () {
    expect(
        JobQuotePdfInput.fromProjection(_projection(item: 'bicicleta'))!
            .itemLabel,
        isNull);
    expect(
        JobQuotePdfInput.fromProjection(_projection(item: 'horquilla'))!
            .itemLabel,
        'Horquilla');
  });

  test('no number or no lines, no quote', () {
    expect(JobQuotePdfInput.fromProjection(null), isNull);
    expect(
        JobQuotePdfInput.fromProjection(_projection(lines: const [])), isNull);
    expect(
      JobQuotePdfInput.fromProjection({..._projection(), 'job_number': ' '}),
      isNull,
    );
  });

  test('half a unit reads with a comma', () {
    const line = JobQuotePdfLine(
      kind: 'other',
      name: 'Grasa',
      quantity: 1.5,
      unitPrice: 2000,
      total: 3000,
    );
    expect(line.quantityLabel, '1,5');
    expect(line.kindLabel, 'Otro');
  });

  test('the quote is drawn, with and without a discount', () async {
    final regular = File('assets/fonts/Barlow-Regular.ttf').readAsBytesSync();
    final bold = File('assets/fonts/Barlow-Bold.ttf').readAsBytesSync();
    final logo = File('assets/images/vinabike_logo.webp').readAsBytesSync();
    for (final discount in [0, 5000]) {
      final bytes = await buildJobQuotePdf(
        JobQuotePdfInput.fromProjection(_projection(discount: discount))!,
        regularFont: ByteData.sublistView(regular),
        boldFont: ByteData.sublistView(bold),
        logo: logo,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    }
  });
}
