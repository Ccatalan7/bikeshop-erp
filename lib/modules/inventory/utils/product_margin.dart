import '../models/inventory_models.dart';

/// Margen de un producto tal como lo lee el dueño en Productos.
///
/// **Precio de venta menos costo con IVA** (decisión del dueño, 2026-09-02):
/// el precio de lista ya trae IVA y el costo se guarda neto, así que la resta
/// que él hace de cabeza es `precio − (costo × 1,19)`. El costo con IVA se
/// redondea a pesos antes de restar, igual que se muestra en pantalla, para
/// que la cuenta visible cuadre: `$600 − $298 = $302`. La tabla y el panel de
/// detalle comparten esta cuenta para no mostrar dos márgenes distintos.
///
/// [percentOverCost] es `null` cuando no hay costo registrado: un costo en
/// cero no es un costo, y un «100 %» calculado sobre él afirmaría una medición
/// que nadie hizo.
class ProductMargin {
  const ProductMargin({
    required this.costWithIva,
    required this.amount,
    required this.percentOverCost,
  });

  /// IVA chileno: el precio de lista lo incluye, el costo no.
  static const double ivaFactor = 1.19;

  /// Costo con IVA, redondeado a pesos (el mismo número que se muestra).
  final double costWithIva;

  /// Precio de venta menos [costWithIva], en pesos.
  final double amount;

  /// Margen sobre el costo con IVA, en puntos porcentuales; `null` sin costo.
  final double? percentOverCost;

  bool get hasCost => percentOverCost != null;

  bool get isBelowCost => hasCost && amount < 0;

  static ProductMargin of(Product product) {
    final costWithIva = (product.cost * ivaFactor).roundToDouble();
    final amount = product.price - costWithIva;
    return ProductMargin(
      costWithIva: costWithIva,
      amount: amount,
      percentOverCost: product.cost > 0 && costWithIva > 0
          ? amount / costWithIva * 100
          : null,
    );
  }
}
