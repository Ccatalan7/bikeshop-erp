import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/quick_expense_receipt_parser.dart';

void main() {
  group('NIC Chile quick-expense OCR', () {
    const parser = QuickExpenseReceiptParser();
    const receiptText = '''
Comprobante de pago WebPay Débito

Su pago ha sido aceptado.
Webpay autorizó el pago con su tarjeta de crédito/débito y ha sido procesado.

Identificador de pago:
21179232
Monto de la transacción:
\$19.980 pesos.
4 últimos dígitos de Tarjeta de Crédito:
3934
Fecha de la transacción:
07 / 17
Código de autorización:
001259
Tipo de transacción:
Venta normal
Número de cuotas:
0

Detalle de la compra:
1. Restauración de dominio : vinabike.cl

Volver al listado de dominios
''';

    test('recognizes the NIC WebPay confirmation as a payment receipt', () {
      expect(parser.looksLikePaymentReceipt(receiptText), isTrue);
    });

    test('extracts the fields needed to prefill the quick expense', () {
      final result = parser.parse(
        receiptText,
        fileName: 'Screenshot 2026-07-17 at 12.26.56 AM.png',
        now: DateTime(2030, 1, 1),
      );

      expect(result.supplierName, 'NIC Chile');
      expect(result.total, 19980);
      expect(result.date, DateTime(2026, 7, 17));
      expect(result.transactionNumber, '21179232');
      expect(result.authorizationCode, '001259');
      expect(result.paymentMethod, 'debit');
      expect(result.purchaseDescription, 'Restauración de dominio vinabike.cl');
      expect(result.isDomainService, isTrue);
      expect(QuickExpenseReceiptParser.domainExpenseAccountCode, '6207-01');
      expect(QuickExpenseReceiptParser.domainExpenseCategoryName,
          'Servicios Digitales');
    });

    test('uses the supplied clock when a screenshot has no dated filename', () {
      final result = parser.parse(
        receiptText,
        fileName: 'comprobante-nic.png',
        now: DateTime(2026, 7, 18),
      );

      expect(result.date, DateTime(2026, 7, 17));
    });

    test('uses the WebPay heading when explanatory copy mentions both cards',
        () {
      final result = parser.parse(
        receiptText.replaceFirst('WebPay Débito', 'WebPay Crédito'),
        fileName: 'Screenshot 2026-07-17.png',
      );

      expect(result.paymentMethod, 'credit');
    });
  });
}
