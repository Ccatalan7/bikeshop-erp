final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Extracts only the order UUID from a server-owned Mercado Pago reference.
///
/// New preferences use `vb1:<tenant>:<order>:<generation>`. Raw UUID values
/// remain readable for callbacks generated before the versioned format.
String? mercadoPagoOrderIdFromExternalReference(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim().toLowerCase();
  if (_uuidPattern.hasMatch(normalized)) return normalized;

  final parts = normalized.split(':');
  if (parts.length != 4 ||
      parts.first != 'vb1' ||
      !_uuidPattern.hasMatch(parts[1]) ||
      !_uuidPattern.hasMatch(parts[2]) ||
      !RegExp(r'^[1-9][0-9]{0,5}$').hasMatch(parts[3])) {
    return null;
  }
  return parts[2];
}
