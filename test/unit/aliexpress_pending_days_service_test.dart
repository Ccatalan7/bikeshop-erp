import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/aliexpress_pending_days_service.dart';

/// Contrato de «qué compras quedaron sin registrar».
///
/// Los números reales del taller siguen `AEDDMMYY` (AE120625 = 12/06/2025) y
/// son el único lugar donde vive la fecha de la factura del día.
void main() {
  test('el número de factura del día se arma y se lee en ambos sentidos', () {
    expect(
      AliExpressPendingDaysService.invoiceNumberForDate(DateTime(2026, 4, 6)),
      'AE060426',
    );
    expect(
      AliExpressPendingDaysService.dateKeyFromInvoiceNumber('AE060426'),
      '2026-04-06',
    );
    expect(
      AliExpressPendingDaysService.dateKeyFromInvoiceNumber('AE120625'),
      '2025-06-12',
    );
  });

  test('un número que no se entiende no se convierte en una fecha', () {
    // Devolver una fecha plausible aquí borraría un día pendiente de la lista.
    for (final number in ['', 'AE0604', 'FAC-1023', 'AE310226', 'AE001326']) {
      expect(
        AliExpressPendingDaysService.dateKeyFromInvoiceNumber(number),
        isNull,
        reason: '«$number» no codifica una fecha válida',
      );
    }
  });

  test('quedan pendientes sólo los días comprados sin factura', () {
    final pending = AliExpressPendingDaysService.pendingDays(
      daysWithOrders: ['2026-04-06', '2026-03-20', '2026-06-15'],
      invoiceNumbers: ['AE200326', 'FAC-9', 'AE010825'],
    );

    // 20/03 ya está facturado; los otros dos no. Más reciente primero.
    expect(pending, ['2026-06-15', '2026-04-06']);
  });

  test('sin compras conocidas no se inventa nada pendiente', () {
    expect(
      AliExpressPendingDaysService.pendingDays(
        daysWithOrders: const [],
        invoiceNumbers: const ['AE060426'],
      ),
      isEmpty,
    );
  });
}
