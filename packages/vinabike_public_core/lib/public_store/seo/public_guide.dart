/// The store's guides (2026-10-08): editor pages with the «Guía» template
/// (`website_pages.template = 'blog'`, the value the page dialog already
/// saved as «Blog»), served at `/guias/<slug>` and listed at `/guias`.
///
/// One rule for every consumer: the HTML storefront (route, page, index),
/// the deploy-time sitemap and the editor's links.
library;

/// `website_pages.template` of a guide.
const websiteGuideTemplate = 'blog';

/// The editor page of the guides' index (`/guias`): its title and
/// description head the list and its blocks follow it, edited like any
/// other page.
const websiteGuidesIndexSlug = 'guias';

/// Where the guides are listed.
const websiteGuidesIndexPath = '/guias';

/// Whether [page] (a `website_pages` row) is a guide. The home and the
/// index's own page never are, whatever their template says.
bool isWebsiteGuidePageRow(Map<Object?, Object?> page) {
  final slug = (page['slug'] ?? '').toString().trim().toLowerCase();
  return (page['template'] ?? '').toString().trim() == websiteGuideTemplate &&
      page['is_home'] != true &&
      slug.isNotEmpty &&
      slug != websiteGuidesIndexSlug;
}

/// The public path of the guide [slug].
String websiteGuidePath(String slug) =>
    '$websiteGuidesIndexPath/${Uri.encodeComponent(slug.trim().toLowerCase())}';

/// Minutes to read [words] at 200 words a minute, at least one.
int websiteGuideReadingMinutes(int words) =>
    words <= 0 ? 1 : (words / 200).ceil();

/// When the guide was published: its `published_at`, else when it was
/// created. Null when the row says neither.
DateTime? websiteGuidePublishedAt(Map<Object?, Object?> page) =>
    _date(page['published_at']) ?? _date(page['created_at']);

/// When the guide last changed (`updated_at`), never before it was
/// published.
DateTime? websiteGuideUpdatedAt(Map<Object?, Object?> page) {
  final published = websiteGuidePublishedAt(page);
  final updated = _date(page['updated_at']);
  if (updated == null) return published;
  if (published != null && updated.isBefore(published)) return published;
  return updated;
}

/// «8 de octubre de 2026», the day in Chile (UTC−3; an hour off in winter
/// only moves a date written near midnight).
String websiteGuideDateLabel(DateTime date) {
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  final local = date.toUtc().subtract(const Duration(hours: 3));
  return '${local.day} de ${months[local.month - 1]} de ${local.year}';
}

/// The Article and BreadcrumbList of a guide's page. The author and the
/// publisher are the store itself (`#negocio`, which every page declares):
/// the guides are written by its workshop.
Map<String, dynamic> buildPublicGuideStructuredData({
  required String storeUrl,
  required String storeName,
  required String guideUrl,
  required String title,
  required String description,
  required String indexTitle,
  DateTime? publishedAt,
  DateTime? updatedAt,
  String imageUrl = '',
}) {
  final headline = _clean(title);
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'Article',
        '@id': '$guideUrl#guia',
        'headline': headline.length > 110
            ? '${headline.substring(0, 109)}…'
            : headline,
        if (_clean(description).isNotEmpty) 'description': _clean(description),
        'url': guideUrl,
        'mainEntityOfPage': guideUrl,
        'inLanguage': 'es-CL',
        if (publishedAt != null)
          'datePublished': publishedAt.toUtc().toIso8601String(),
        if (updatedAt != null)
          'dateModified': updatedAt.toUtc().toIso8601String(),
        if (imageUrl.trim().isNotEmpty) 'image': [imageUrl.trim()],
        'author': {
          '@type': 'Organization',
          'name': _clean(storeName),
          'url': storeUrl,
        },
        'publisher': {'@id': '$storeUrl/#negocio'},
      },
      {
        '@type': 'BreadcrumbList',
        'itemListElement': [
          for (final (index, crumb) in [
            ('Inicio', storeUrl),
            (_clean(indexTitle), '$storeUrl$websiteGuidesIndexPath'),
            (headline, guideUrl),
          ].indexed)
            {
              '@type': 'ListItem',
              'position': index + 1,
              'name': crumb.$1,
              'item': crumb.$2,
            },
        ],
      },
    ],
  };
}

/// The CollectionPage, ItemList and BreadcrumbList of the guides' index.
Map<String, dynamic> buildPublicGuidesIndexStructuredData({
  required String storeUrl,
  required String title,
  required String description,
  required List<({String url, String name})> guides,
}) {
  final indexUrl = '$storeUrl$websiteGuidesIndexPath';
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'CollectionPage',
        'name': _clean(title),
        if (_clean(description).isNotEmpty) 'description': _clean(description),
        'url': indexUrl,
        'inLanguage': 'es-CL',
      },
      {
        '@type': 'ItemList',
        'numberOfItems': guides.length,
        'itemListElement': [
          for (final (index, guide) in guides.indexed)
            {
              '@type': 'ListItem',
              'position': index + 1,
              'url': guide.url,
              'name': _clean(guide.name),
            },
        ],
      },
      {
        '@type': 'BreadcrumbList',
        'itemListElement': [
          {
            '@type': 'ListItem',
            'position': 1,
            'name': 'Inicio',
            'item': storeUrl,
          },
          {
            '@type': 'ListItem',
            'position': 2,
            'name': _clean(title),
            'item': indexUrl,
          },
        ],
      },
    ],
  };
}

DateTime? _date(Object? value) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

String _clean(String text) => text
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
