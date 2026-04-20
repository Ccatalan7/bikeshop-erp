enum StockAdjustmentOrigin {
  productForm('product_form', 'Formulario producto'),
  massEditPanel('mass_edit_panel', 'Edicion masiva'),
  manualService('manual_service', 'Ajuste manual');

  const StockAdjustmentOrigin(this.value, this.label);

  final String value;
  final String label;
}

StockAdjustmentOrigin? stockAdjustmentOriginFromValue(String? value) {
  if (value == null) return null;

  for (final origin in StockAdjustmentOrigin.values) {
    if (origin.value == value) {
      return origin;
    }
  }

  return null;
}

String? stockAdjustmentOriginDisplay(String? value) {
  return stockAdjustmentOriginFromValue(value)?.label;
}
