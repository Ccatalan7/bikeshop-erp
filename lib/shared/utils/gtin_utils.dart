String firstValidGtin(Iterable<Object?> values) {
  for (final value in values) {
    final normalized = normalizeGtin(value);
    if (normalized != null) return normalized;
  }
  return '';
}

String? normalizeGtin(Object? rawValue) {
  final value = (rawValue ?? '').toString().trim().replaceAll(
        RegExp(r'[\s-]+'),
        '',
      );
  if (!RegExp(r'^\d+$').hasMatch(value)) return null;
  if (!const {8, 12, 13, 14}.contains(value.length)) return null;
  if (_hasRestrictedGs1Prefix(value)) return null;
  if (!_hasValidCheckDigit(value)) return null;
  return value;
}

bool isValidGtin(Object? value) => normalizeGtin(value) != null;

bool _hasRestrictedGs1Prefix(String value) {
  // GTIN-14 begins with a packaging indicator; the GS1 prefix follows it.
  final gs1Payload = value.length == 14 ? value.substring(1) : value;
  return gs1Payload.startsWith('02') ||
      gs1Payload.startsWith('04') ||
      gs1Payload.startsWith('2') ||
      gs1Payload.startsWith('98') ||
      gs1Payload.startsWith('99');
}

bool _hasValidCheckDigit(String value) {
  final digits = value.codeUnits.map((unit) => unit - 48).toList();
  final checkDigit = digits.last;
  var sum = 0;
  var positionFromRight = 1;

  for (var index = digits.length - 2; index >= 0; index--) {
    sum += digits[index] * (positionFromRight.isOdd ? 3 : 1);
    positionFromRight++;
  }

  return (10 - (sum % 10)) % 10 == checkDigit;
}
