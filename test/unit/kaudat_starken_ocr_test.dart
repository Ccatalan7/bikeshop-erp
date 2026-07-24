import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/invoice_parser_service.dart';

void main() {
  group('Kaudat / Starken OCR', () {
    test(
        'reads the Kaudat transport factura without using recipient as supplier',
        () {
      const text = '''
KAUDAT  SpA.Giro:AGENTE COMISIONISTA
 GIROS NACIONALES E INTERNACIONALES
R.U.T.: 76.211.240-K
FACTURA ELECTRONICA
Nº 13486798
S.I.I. - SANTIAGO PONIENTE
Casa Matriz: Avenida Lib. Bdo. O´Higgins 3750 oficina 404, Estación Central
Fonos: 490-7414
Sucursal: CALLE 10MA 2450,VALPARAISO,VALPARAISO
Señor(es): NEWEN SPA.
R.U.T.: 77.541.999-7
Dirección: ALVAREZ 32 LOCAL 17
Ciudad: VINA DEL MAR
Giro: BICICLETAS Y SU REPUESTOS
Comuna:  VINA DEL MAR
Fecha Emision: 2/06/2026
Vencimiento: 2/06/2026
TIPO DOCUMENTO: Factura Electronica
FOLIO:
13486798
FECHA:
2/06/2026
MONTO NETO:
8.437
19% I.V.A.:
1.603
TOTAL:
10.040
DESCRIPCION DESCRIPCION MONTOMONTO
COURIER / FLETE: [271308755] 8.437
SON:DIEZ MIL CUARENTA PESOS PESOS.
---------------------------------------------------------------------------
NOMBRE: NEWEN SPA.
RUT: 77.541.999-7
Nº CLIENTE:
Nº DOCUMENTO: 13486798
Total a Pagar: 10.040
''';

      final invoice = InvoiceParserService().parseInvoiceFromText(text);

      expect(invoice.rut, '76.211.240-K');
      expect(invoice.invoiceNumber, '13486798');
      expect(invoice.date, DateTime(2026, 6, 2));
      expect(invoice.netAmount, 8437);
      expect(invoice.taxAmount, 1603);
      expect(invoice.total, 10040);
      expect(invoice.supplierName, contains('KAUDAT'));
      expect(invoice.supplierName, isNot(contains('Giro')));
      expect(invoice.supplierName, isNot(contains('NEWEN')));
    });

    test('supplier identity names include legal/trade/owner aliases', () {
      final supplier = Supplier.fromJson({
        'id': 'supplier-id',
        'tenant_id': 'tenant-id',
        'name': 'Starken',
        'legal_name': 'Kaudat SpA',
        'trade_name': 'Starken',
        'owner_name': 'Kaudat SpA',
        'aliases': ['Kaudat', 'KAUDAT SPA'],
        'bank_details': <String, dynamic>{},
        'payment_terms': 'net30',
        'default_tax_treatment': 'tax_included',
        'ocr_template': <String, dynamic>{},
        'is_active': true,
        'created_at': '2026-06-03T00:00:00.000Z',
        'updated_at': '2026-06-03T00:00:00.000Z',
      });

      expect(supplier.displayName, 'Starken');
      expect(supplier.identityNames, containsAll(['Starken', 'Kaudat SpA']));
      expect(supplier.identityNames, contains('Kaudat'));
      expect(supplier.toJson()['aliases'], ['Kaudat', 'KAUDAT SPA']);
    });
  });
}
