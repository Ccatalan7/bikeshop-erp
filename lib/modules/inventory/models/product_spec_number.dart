import '../utils/spec_rule_evaluator.dart';

/// Input text may use the operator's decimal comma. Canonical wire values use
/// decimal strings, including on web; they never travel through double/int.
/// An older mounted draft may still contain a machine number. Reject unsafe
/// magnitudes instead of pretending to recover digits lost during decoding.
SpecRuleDecimal? productSpecNumber(Object? value) {
  if (value is num && (!value.isFinite || value.abs() > 9007199254740991))
    return null;
  return specRuleNumber(value);
}

String productSpecNumberWireValue(Object? value) {
  final number = productSpecNumber(value);
  if (number == null) {
    throw const FormatException(
        'Número inválido o fuera del dominio admitido.');
  }
  return number.canonical;
}

/// Missing observations are handled by the fiche's required/applicable rules.
/// This function validates a present value without converting it to binary.
String? productSpecNumberErrorCode(Object? value, Map<String, dynamic> rules) {
  final number = productSpecNumber(value);
  if (number == null) return 'type';
  final minimum = productSpecNumber(rules['min']);
  final maximum = productSpecNumber(rules['max']);
  if (rules['min'] != null && minimum == null ||
      rules['max'] != null && maximum == null) return 'invalid_rules';
  if (minimum != null && number.compareTo(minimum) < 0) return 'min';
  if (maximum != null && number.compareTo(maximum) > 0) return 'max';
  if (rules['positive'] == true &&
      number.compareTo(SpecRuleDecimal.tryParse('0')!) <= 0) return 'positive';
  if (rules['integer'] == true && number.exponent < 0) return 'integer';
  return null;
}
