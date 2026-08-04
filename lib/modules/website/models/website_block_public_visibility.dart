import 'dart:convert';

import 'website_responsive_authoring.dart';

const websitePublicBreakpoints = <String>[
  'desktop',
  'tablet',
  'mobile',
];

String websitePublicBreakpointForWidth(double width) {
  if (width < 640) return 'mobile';
  if (width < 1024) return 'tablet';
  return 'desktop';
}

/// Resolves the semantic viewport using the document's persisted generation.
///
/// Existing documents keep the historical 640/1024 bands. A document becomes
/// canonical only after an explicit responsive edit writes schema version 2,
/// at which point the shared 600/900 owner is used.
WebsiteViewport websitePublicViewportForBlockDataWidth(
  Map<String, dynamic> blockData,
  double width,
) =>
    WebsiteResponsiveDataCodec.viewportForDocumentWidth(blockData, width);

bool isWebsiteBlockVisibleAtLogicalWidth(
  Map<String, dynamic> block,
  double width,
) {
  if (block['is_visible'] == false) return false;
  final rawData = block['block_data'];
  final blockData = rawData is Map
      ? rawData.map((key, value) => MapEntry(key.toString(), value))
      : const <String, dynamic>{};
  final viewport = websitePublicViewportForBlockDataWidth(blockData, width);
  return isWebsiteBlockVisibleAtPublicBreakpoint(block, viewport.wireName);
}

Map<String, bool> normalizeWebsiteBlockPublicVisibility(dynamic raw) {
  final visibility = <String, bool>{
    for (final breakpoint in websitePublicBreakpoints) breakpoint: true,
  };

  dynamic source = raw;
  if (source is String) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      source = null;
    } else {
      try {
        final decoded = jsonDecode(trimmed);
        source = decoded is Map ? decoded : null;
      } on FormatException {
        source = null;
      }
    }
  }

  if (source is Map) {
    source.forEach((key, value) {
      final breakpoint = key.toString();
      if (!visibility.containsKey(breakpoint)) return;
      final parsed = _parseWebsiteVisibilityBoolean(value);
      if (parsed != null) visibility[breakpoint] = parsed;
    });
  }

  return Map.unmodifiable(visibility);
}

bool isWebsiteBlockVisibleOnAnyPublicBreakpoint(
  Map<String, dynamic> block,
) {
  if (block['is_visible'] == false) return false;
  final blockData = block['block_data'];
  final visibility = normalizeWebsiteBlockPublicVisibility(
    blockData is Map ? blockData['visibility'] : null,
  );
  return visibility.values.any((isVisible) => isVisible);
}

bool isWebsiteBlockVisibleAtPublicBreakpoint(
  Map<String, dynamic> block,
  String breakpoint,
) {
  if (block['is_visible'] == false) return false;
  final blockData = block['block_data'];
  final visibility = normalizeWebsiteBlockPublicVisibility(
    blockData is Map ? blockData['visibility'] : null,
  );
  return visibility[breakpoint] == true;
}

bool? _parseWebsiteVisibilityBoolean(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' ||
        normalized == '1' ||
        normalized == 'si' ||
        normalized == 'sí') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return null;
}
