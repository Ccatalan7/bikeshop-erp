/// Días con compras en AliExpress que todavía no tienen factura en el ERP.
///
/// Por qué existe: una compra hecha fuera del navegador del ERP —desde el
/// teléfono, otro computador, o simplemente antes de abrir el ERP— no deja
/// rastro en el sistema hasta que alguien recuerda importarla. El correo no
/// sirve de disparador: AliExpress sólo envía avisos de *entrega*, y su número
/// es el seguimiento del courier, que no permite ligarlo a un pedido ni a una
/// factura (verificado en la bandeja real el 2026-08-06).
///
/// La fuente confiable es la propia cuenta de AliExpress, que ya se consulta
/// para armar la factura del día: esa consulta deja como subproducto el índice
/// de días con pedidos. Contrastarlo con las facturas ya emitidas dice
/// exactamente qué días quedaron sin registrar, sin importar dónde se compró.
class AliExpressPendingDaysService {
  const AliExpressPendingDaysService();

  /// Número de factura canónico para un día: `AEDDMMYY`.
  ///
  /// Es el formato que el taller ya usa (AE120625 = 12/06/25) y el que hace
  /// única la factura por proveedor y día en la base.
  static String invoiceNumberForDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = (date.year % 100).toString().padLeft(2, '0');
    return 'AE$day$month$year';
  }

  /// Fecha (`yyyy-MM-dd`) codificada en un número `AEDDMMYY`.
  ///
  /// Devuelve null ante cualquier otra forma: un número que no se entiende se
  /// reporta como desconocido, nunca se convierte en una fecha plausible que
  /// haría desaparecer un día pendiente de la lista.
  static String? dateKeyFromInvoiceNumber(String invoiceNumber) {
    final match = RegExp(r'^AE(\d{2})(\d{2})(\d{2})$', caseSensitive: false)
        .firstMatch(invoiceNumber.trim());
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = 2000 + int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    // Rechaza combinaciones inexistentes (31/02) sin depender del rollover.
    final parsed = DateTime(year, month, day);
    if (parsed.month != month || parsed.day != day) return null;
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  /// Días con compras que aún no tienen factura, del más reciente al más
  /// antiguo.
  ///
  /// [daysWithOrders] y [invoiceNumbers] vienen de fuentes distintas —la API
  /// del proveedor y la base del ERP— y por eso el contraste es útil.
  static List<String> pendingDays({
    required Iterable<String> daysWithOrders,
    required Iterable<String> invoiceNumbers,
  }) {
    final invoiced = <String>{
      for (final number in invoiceNumbers)
        if (dateKeyFromInvoiceNumber(number) case final key?) key,
    };
    final pending = <String>{
      for (final day in daysWithOrders)
        if (day.trim().isNotEmpty && !invoiced.contains(day.trim())) day.trim(),
    }.toList()
      ..sort();
    return pending.reversed.toList();
  }
}
