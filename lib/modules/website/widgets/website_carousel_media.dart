/// Returns the network images owned by one saved carousel slide.
///
/// The traversal intentionally follows the persisted slide tree instead of
/// knowing about a specific campaign. It therefore includes the slide
/// background, nested Canvas image layers, responsive variants, and future
/// editor fields that keep the established image URL naming contract.
List<String> collectWebsiteCarouselSlideImageUrls(
  Map<String, dynamic> slide,
) {
  final urls = <String>{};

  void visit(dynamic value, {String? fieldName}) {
    if (value is Map) {
      for (final entry in value.entries) {
        visit(entry.value, fieldName: entry.key.toString());
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        visit(item, fieldName: fieldName);
      }
      return;
    }
    if (value is! String || !_isImageField(fieldName)) return;

    final candidate = value.trim();
    final uri = Uri.tryParse(candidate);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    urls.add(candidate);
  }

  visit(slide);
  return urls.toList(growable: false);
}

bool websiteCarouselSlideUsesComposition(Map<String, dynamic> slide) {
  if (slide['useComposition'] == true) return true;
  final elements = slide['elements'];
  return elements is List && elements.isNotEmpty;
}

/// Returns the minimal warm-up order for a carousel's current playback state.
///
/// The visible slide is warmed first so layered compositions appear atomically,
/// followed only by the next autoplay slide. Preloading every saved slide at
/// startup competes with the storefront's critical requests and can download
/// several megabytes that the visitor never sees.
List<int> websiteCarouselPreloadOrder({
  required int slideCount,
  required int currentIndex,
}) {
  if (slideCount <= 0) return const <int>[];

  final normalizedIndex = currentIndex % slideCount;
  if (slideCount == 1) return <int>[normalizedIndex];

  return <int>[
    normalizedIndex,
    (normalizedIndex + 1) % slideCount,
  ];
}

bool _isImageField(String? fieldName) {
  if (fieldName == null) return false;
  final normalized = fieldName.toLowerCase();
  return normalized == 'backgroundimage' ||
      normalized == 'backgroundimageurl' ||
      normalized == 'imageurl' ||
      normalized == 'mobileimageurl' ||
      normalized == 'desktopimageurl' ||
      normalized == 'posterurl' ||
      normalized.endsWith('imageurl');
}
