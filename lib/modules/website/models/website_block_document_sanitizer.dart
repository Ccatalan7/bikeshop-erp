/// Removes editor-only values from one persisted block-data object.
///
/// The rule is deliberately type-aware. `activeElementId` is transient only
/// for a standalone Canvas root and for a Carousel slide that composes Canvas
/// content. The same key may be legitimate business content in another block
/// or nested element, so a recursive key scrub would corrupt authored data.
Map<String, dynamic> sanitizeWebsiteBlockDataForPersistence({
  required String blockType,
  required Map<String, dynamic> data,
}) {
  final normalizedType = blockType.trim().toLowerCase();
  final sanitized = Map<String, dynamic>.from(data);

  if (normalizedType == 'canvas') {
    sanitized.remove('activeElementId');
    return sanitized;
  }

  if (normalizedType != 'carousel') return sanitized;

  final rawSlides = sanitized['slides'];
  if (rawSlides is! List) return sanitized;

  sanitized['slides'] = rawSlides.map<dynamic>((rawSlide) {
    if (rawSlide is! Map) return rawSlide;
    return Map<String, dynamic>.from(rawSlide)..remove('activeElementId');
  }).toList(growable: false);
  return sanitized;
}

/// Returns a block document whose persisted data cannot contain editor-only
/// Canvas selection.
///
/// Both supported data aliases are sanitized when present. Callers that own
/// deeper copy semantics should copy before invoking this helper; only the
/// block, data map, Carousel slide list, and slide maps are copied here.
Map<String, dynamic> sanitizeWebsiteBlockForPersistence(
  Map<String, dynamic> block,
) {
  final sanitized = Map<String, dynamic>.from(block);
  final blockType =
      (sanitized['block_type'] ?? sanitized['type'] ?? '').toString();

  for (final dataKey in const <String>['block_data', 'data']) {
    final rawData = sanitized[dataKey];
    if (rawData is! Map) continue;
    sanitized[dataKey] = sanitizeWebsiteBlockDataForPersistence(
      blockType: blockType,
      data: Map<String, dynamic>.from(rawData),
    );
  }
  return sanitized;
}

List<Map<String, dynamic>> sanitizeWebsiteBlocksForPersistence(
  Iterable<Map<String, dynamic>> blocks,
) =>
    blocks.map(sanitizeWebsiteBlockForPersistence).toList();
