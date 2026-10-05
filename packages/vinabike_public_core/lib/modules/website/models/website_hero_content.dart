import 'website_action.dart';

/// The hero's button: the visible editor fields (`ctaText`/`buttonText`/
/// `label` and `ctaLink`/`buttonLink`/`link`) when present, otherwise the
/// first navigate action; outlined unless the block says otherwise. `null`
/// when it has no label. Flutter's hero and the HTML storefront read it here.
WebsiteActionValue? resolveWebsiteHeroAction(Map<String, dynamic> data) {
  const labelKeys = <String>['ctaText', 'buttonText', 'label'];
  const hrefKeys = <String>['ctaLink', 'buttonLink', 'link'];
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
