import 'website_canvas_responsive_document.dart';
import 'website_responsive_authoring.dart';

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
  var sanitized = _deepCopyWebsiteMap(data);

  if (normalizedType == 'canvas') {
    sanitized.remove('activeElementId');
    return WebsiteResponsiveDataCodec.normalize(
      _sanitizeCanvasLayers(sanitized),
      transientPropertyKeys: const {'activeElementId'},
    );
  }

  if (normalizedType != 'carousel') {
    return WebsiteResponsiveDataCodec.normalize(sanitized);
  }

  final rawSlides = sanitized['slides'];
  if (rawSlides is! List) {
    return WebsiteResponsiveDataCodec.normalize(sanitized);
  }

  sanitized['slides'] = rawSlides.map<dynamic>((rawSlide) {
    if (rawSlide is! Map) return rawSlide;
    final slide = _deepCopyWebsiteMap(rawSlide)..remove('activeElementId');
    return WebsiteResponsiveDataCodec.normalize(
      // A slide can host Canvas content, and its layers own the same nested
      // responsive container as a standalone Canvas block.
      _sanitizeCanvasLayers(slide),
      transientPropertyKeys: const {'activeElementId'},
    );
  }).toList(growable: false);
  sanitized = WebsiteResponsiveDataCodec.normalize(sanitized);
  return sanitized;
}

/// Returns a block document whose persisted data cannot contain editor-only
/// Canvas selection.
///
/// Both supported data aliases are sanitized when present. Callers that own
/// deeper copy semantics do not need to copy first: every authored nested map,
/// list, set and responsive branch is detached before normalization.
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

/// Normalises each Canvas layer with ITS own policies.
///
/// A layer owns a nested responsive container, so the root normalisation
/// cannot reach it: without this pass an empty override map, an override equal
/// to the base or a transient selection key could survive inside a layer.
/// Documents without layers come back untouched.
Map<String, dynamic> _sanitizeCanvasLayers(Map<String, dynamic> data) {
  final raw = data[WebsiteCanvasResponsivePolicy.elementsKey];
  if (raw is! List) return data;
  final next = Map<String, dynamic>.from(data);
  next[WebsiteCanvasResponsivePolicy.elementsKey] = raw
      .map<dynamic>(
        (layer) => layer is Map
            ? WebsiteCanvasResponsiveDocument.normalizeLayer(layer)
            : layer,
      )
      .toList(growable: false);
  return next;
}

Map<String, dynamic> _deepCopyWebsiteMap(Map<dynamic, dynamic> source) =>
    source.map(
      (key, value) => MapEntry(key.toString(), _deepCopyWebsiteValue(value)),
    );

dynamic _deepCopyWebsiteValue(dynamic value) {
  if (value is Map) return _deepCopyWebsiteMap(value);
  if (value is List) {
    return value.map(_deepCopyWebsiteValue).toList(growable: false);
  }
  if (value is Set) return value.map(_deepCopyWebsiteValue).toSet();
  return value;
}
