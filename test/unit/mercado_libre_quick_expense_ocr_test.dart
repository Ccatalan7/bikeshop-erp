import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/invoice_parser_service.dart';

void main() {
  group('Mercado Libre delegated-seller invoice OCR', () {
    const rawText = '''
24/07/2026 17:44 Página 1
Nº 14329694
FACTURA ELECTRÓNICA
R.U.T.: 77398220-1
MERCADOLIBRE CHILE LTDA
OTRAS ACTIVIDADES DE VENTA AL POR MENOR EN COMERCIOS
Por cuenta y orden del vendedor
DAMAITONG CHILE SPA.
R.U.T.: 77359337-K
Cliente
Nombre:
RUT:
Fecha emisión:
NEWEN SPA
77541999-7
24/07/2026
Nº lín.
Nombre del producto
Cant.
Precio unit.
Monto lín.
IndExe
% Desc.
Total descuento
% Recargo
Total recargo
Detalle
Imp. Ad.
1
Cat6 Rj45 Cable De Red Lan Alta DeDatos 20m Color Negro
1
\$7.218
\$7.218
2
Costo de envio
1
\$4.193
\$4.193
Importes totales
Monto neto
\$11.411
IVA
\$2.169
(19%)
MONTO TOTAL
\$13.580
''';

    test('uses the named seller instead of marketplace or page header', () {
      final parsed = InvoiceParserService().parseInvoiceFromText(rawText);

      expect(parsed.supplierName, 'DAMAITONG CHILE SPA');
      expect(parsed.rut, '77.359.337-K');
      expect(parsed.invoiceNumber, '14329694');
      expect(parsed.date, DateTime(2026, 7, 24));
      expect(parsed.netAmount, 11411);
      expect(parsed.taxAmount, 2169);
      expect(parsed.total, 13580);
    });

    test('extracts merchandise and shipping as separate reviewable lines', () {
      final parsed = InvoiceParserService().parseInvoiceFromText(rawText);

      expect(parsed.lineItems, hasLength(2));
      expect(
        parsed.lineItems.first.description,
        'Cat6 Rj45 Cable De Red Lan Alta DeDatos 20m Color Negro',
      );
      expect(parsed.lineItems.first.quantity, 1);
      expect(parsed.lineItems.first.unitPrice, 7218);
      expect(parsed.lineItems.first.total, 7218);
      expect(parsed.lineItems.last.description, 'Costo de envio');
      expect(parsed.lineItems.last.total, 4193);
    });
  });
}
