import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

typedef ProductIdentityTraceSink = void Function(Map<String, Object?> event);

/// One redacted, machine-readable trace for the complete OCR identity path.
///
/// The trace deliberately permits catalog names, ids, SKUs, typed identity,
/// gates and scores because those are the facts needed to reproduce a bad
/// match. It never permits prompts, source titles, image bytes/base64, signed
/// URLs, credentials or authorization material. Callers log lengths and
/// digests for those inputs instead.
class ProductIdentityTrace {
  const ProductIdentityTrace._();

  static const String logPrefix = '[OCR_AI_TRACE]';

  static const Set<String> _forbiddenKeys = <String>{
    'authorization',
    'access_token',
    'refresh_token',
    'api_key',
    'apikey',
    'password',
    'secret',
    'prompt',
    'system_instruction',
    'contents',
    'inline_data',
    'base64',
    'image_bytes',
    'image_url',
    'signed_url',
    'raw_title',
    'source_title',
  };

  /// Stable across row rebuilds for the same evidence revision, but carries no
  /// supplier text, listing id or variant value itself.
  static String idFor({
    required String scope,
    required String rowKey,
    required String revision,
  }) {
    final digest = crypto.sha256.convert(
      utf8.encode('$scope\u001f$rowKey\u001f$revision'),
    );
    return digest.toString().substring(0, 20);
  }

  static String digestText(String value) =>
      crypto.sha256.convert(utf8.encode(value)).toString().substring(0, 16);

  /// Correlates image evidence without ever logging bytes, base64 or URLs.
  ///
  /// This is intentionally a content digest rather than a perceptual match:
  /// equal values prove the exact same encoded asset reached both sides of an
  /// adjudication, while different values simply mean the images still need
  /// semantic comparison.
  static String digestBytes(List<int> value) =>
      crypto.sha256.convert(value).toString().substring(0, 16);

  static void emit({
    required String traceId,
    required String event,
    Map<String, Object?> data = const <String, Object?>{},
    ProductIdentityTraceSink? sink,
  }) {
    if (traceId.trim().isEmpty || event.trim().isEmpty) return;
    final sanitized = _sanitizeMap(data);
    final record = Map<String, Object?>.unmodifiable(<String, Object?>{
      'event': event.trim(),
      'trace_id': traceId.trim(),
      ...sanitized,
    });
    sink?.call(record);
    if (kDebugMode) {
      debugPrintSynchronously('$logPrefix ${jsonEncode(record)}');
    }
  }

  static Map<String, Object?> _sanitizeMap(Map<String, Object?> values) {
    final result = <String, Object?>{};
    for (final entry in values.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || _isForbiddenKey(key)) continue;
      result[key] = _sanitizeValue(entry.value);
    }
    return result;
  }

  static bool _isForbiddenKey(String key) {
    final normalized = key.toLowerCase();
    return _forbiddenKeys.any(
      (forbidden) =>
          normalized == forbidden || normalized.endsWith('_$forbidden'),
    );
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is bool || value is num) return value;
    if (value is String) {
      final singleLine = value.trim().replaceAll(RegExp(r'[\r\n]+'), ' ');
      return singleLine.length <= 500
          ? singleLine
          : '${singleLine.substring(0, 500)}…';
    }
    if (value is Map) {
      return _sanitizeMap(<String, Object?>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      });
    }
    if (value is Iterable) {
      return <Object?>[
        for (final item in value.take(128)) _sanitizeValue(item),
      ];
    }
    return value.runtimeType.toString();
  }
}
