import 'package:flutter/foundation.dart';

bool isMeaningfulProductSpecValue(dynamic value) {
  if (value == null) {
    return false;
  }
  if (value is String) {
    return value.trim().isNotEmpty;
  }
  if (value is List) {
    return value.isNotEmpty;
  }
  return true;
}

bool areProductSpecValuesEquivalent(dynamic left, dynamic right) {
  if (left is List || right is List) {
    final leftValues = (left is List ? left : [left])
        .where((value) => value != null)
        .map((value) => value.toString())
        .toList()
      ..sort();
    final rightValues = (right is List ? right : [right])
        .where((value) => value != null)
        .map((value) => value.toString())
        .toList()
      ..sort();
    return listEquals(leftValues, rightValues);
  }
  return left?.toString() == right?.toString();
}

Map<String, dynamic> omitAutoDerivedProductSpecValues({
  required Map<String, dynamic> values,
  required Map<String, dynamic> autoDerivedValues,
}) {
  final persistedValues = Map<String, dynamic>.from(values);

  for (final entry in autoDerivedValues.entries) {
    if (areProductSpecValuesEquivalent(
        persistedValues[entry.key], entry.value)) {
      persistedValues.remove(entry.key);
    }
  }

  return persistedValues;
}

Map<String, dynamic> pruneStaleAutoDerivedProductSpecValues({
  required Map<String, dynamic> baseValues,
  required Set<String> manualKeys,
  required Map<String, dynamic> previousAutoValues,
}) {
  final resolvedValues = Map<String, dynamic>.from(baseValues);

  for (final entry in previousAutoValues.entries) {
    if (manualKeys.contains(entry.key)) {
      continue;
    }
    if (areProductSpecValuesEquivalent(
        resolvedValues[entry.key], entry.value)) {
      resolvedValues.remove(entry.key);
    }
  }

  return resolvedValues;
}
