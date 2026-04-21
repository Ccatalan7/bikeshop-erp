const Map<String, String> kBottomBracketFamilyOptions = {
  'bsa_threaded': 'BSA roscado',
  'pressfit': 'Pressfit',
  'bb30_pf30': 'BB30 / PF30',
  'mid': 'Mid / BMX',
  'one_piece': 'One-piece',
  'other': 'Otro',
  'unknown': 'Desconocido',
};

String? bottomBracketFamilyLabel(String? rawValue) {
  if (rawValue == null || rawValue.isEmpty) {
    return null;
  }

  return kBottomBracketFamilyOptions[rawValue] ?? rawValue;
}

bool isKnownBottomBracketFamily(String? rawValue) {
  return rawValue != null && rawValue.isNotEmpty && rawValue != 'unknown';
}
