/// The schema.org node of one of the store's own pages: `AboutPage` for
/// `/nosotros`, `ContactPage` for `/contacto` and `WebPage` for the rest,
/// part of the store's `WebSite`.
Map<String, dynamic> buildPublicPageStructuredData({
  required String slug,
  required String title,
  required String description,
  required String pageUrl,
  required String storeUrl,
  required String storeName,
}) {
  return {
    '@context': 'https://schema.org',
    '@type': switch (slug) {
      'contacto' => 'ContactPage',
      'nosotros' => 'AboutPage',
      _ => 'WebPage',
    },
    'name': title,
    'description': description,
    'url': pageUrl,
    'isPartOf': {'@type': 'WebSite', 'name': storeName, 'url': storeUrl},
  };
}
