import 'website_action.dart';

/// The hero's button: the visible editor fields (`ctaText`/`buttonText`/
/// `label` and `ctaLink`/`buttonLink`/`link`) when present, otherwise the
/// first navigate action; outlined unless the block says otherwise. `null`
/// when it has no label. Flutter's hero and the HTML storefront read it here.
WebsiteActionValue? resolveWebsiteHeroAction(Map<String, dynamic> data) =>
    _resolveVisibleFieldAction(
      data,
      labelKeys: WebsiteButtonFields.hero.label,
      hrefKeys: WebsiteButtonFields.hero.href,
    );

/// A carousel slide's button, by the hero's rule with the slide's fields
/// (`ctaText`/`buttonText` and `ctaLink`/`buttonLink`). Flutter's carousel
/// and the HTML storefront read it here.
WebsiteActionValue? resolveWebsiteCarouselSlideAction(
  Map<String, dynamic> slide,
) => _resolveVisibleFieldAction(
  slide,
  labelKeys: WebsiteButtonFields.slide.label,
  hrefKeys: WebsiteButtonFields.slide.href,
);

WebsiteActionValue? _resolveVisibleFieldAction(
  Map<String, dynamic> data, {
  required List<String> labelKeys,
  required List<String> hrefKeys,
}) {
  ({bool present, String value}) firstPresent(List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key)) {
        return (present: true, value: data[key]?.toString() ?? '');
      }
    }
    return (present: false, value: '');
  }

  final labelField = firstPresent(labelKeys);
  final hrefField = firstPresent(hrefKeys);
  final resolved = WebsiteActionValue.resolvePrimary(
    data,
    labelKeys: labelKeys,
    hrefKeys: hrefKeys,
    variantKeys: const <String>['actionVariant'],
    defaultLabel: '',
    defaultHref: '',
    defaultVariant: WebsiteActionVariant.outline,
  );
  final label = (labelField.present ? labelField.value : resolved?.label ?? '')
      .trim();
  if (label.isEmpty) return null;
  final href = (hrefField.present ? hrefField.value : resolved?.href ?? '')
      .trim();
  final variant = data.containsKey('actionVariant')
      ? WebsiteActionVariant.fromStorage(
          data['actionVariant']?.toString(),
          fallback: WebsiteActionVariant.outline,
        )
      : resolved?.variant ?? WebsiteActionVariant.outline;
  return WebsiteActionValue(label: label, href: href, variant: variant);
}

/// The YouTube video id in a `youtube.com/watch?v=`, `youtube.com/embed/`,
/// `youtube.com/v/` or `youtu.be/` link, or `null`. Flutter's video banner
/// and carousel and the HTML storefront read it here.
String? websiteYouTubeVideoId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.host.contains('youtube.com')) {
    final videoId = uri.queryParameters['v'];
    if (videoId != null && videoId.isNotEmpty) return videoId;
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      final embed = segments.indexOf('embed');
      final v = segments.indexOf('v');
      if (embed != -1 && embed + 1 < segments.length) {
        return segments[embed + 1];
      }
      if (v != -1 && v + 1 < segments.length) return segments[v + 1];
    }
  }
  if (uri.host.contains('youtu.be')) {
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) return segments.first;
  }
  return null;
}
