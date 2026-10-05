import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/public_store/models/public_category_route.dart';

const _published = '46a51a87-aa3a-430c-a6e1-af48c8d74541';
const _hidden = 'ef796c68-07dc-4197-b0ab-4f82b2621101';
const _frenos = '5ef32804-4d13-44d6-955d-70d6ff27a85e';

// Production on 2026-10-05: «Cambios» and «Frenos» each exist twice, one
// published under Componentes and one hidden elsewhere.
final _categories = <PublicCategoryRouteCandidate>[
  (
    id: _published,
    name: 'Cambios',
    fullPath: 'Componentes > Cambios',
    isPublished: true,
  ),
  (id: _hidden, name: 'Cambios', fullPath: 'Taller > Cambios', isPublished: false),
  (id: _frenos, name: 'Frenos', fullPath: 'Componentes > Frenos', isPublished: true),
];

String? _resolve(
  String value, {
  WebsiteCatalogPresentationRegistry presentations =
      const WebsiteCatalogPresentationRegistry({}),
}) => resolvePublishedCategoryRouteValue(
  value,
  presentations: presentations,
  categories: _categories,
);

void main() {
  test('a name shared with a hidden category opens the published one', () {
    expect(_resolve('cambios'), _published);
    expect(_resolve('Cambios'), _published);
    expect(_resolve('componentes-cambios'), _published);
  });

  test('a UUID opens only a published category', () {
    expect(_resolve(_published), _published);
    expect(_resolve(_hidden), isNull);
  });

  test('two published categories with the same name fail closed', () {
    final both = [
      ..._categories,
      (
        id: 'c0000000-0000-4000-8000-000000000009',
        name: 'Frenos',
        fullPath: 'Repuestos > Frenos',
        isPublished: true,
      ),
    ];
    expect(
      resolvePublishedCategoryRouteValue(
        'frenos',
        presentations: const WebsiteCatalogPresentationRegistry({}),
        categories: both,
      ),
      isNull,
    );
  });

  test('a saved slug belongs to its category and never falls through', () {
    final presentations = WebsiteCatalogPresentationRegistry({
      _hidden: WebsiteCatalogPresentation.fallback(
        categoryId: _hidden,
        categoryName: 'Cambios',
      ),
    });
    // The editor gave «cambios» to the hidden category: nothing opens, not
    // even the published category with the same name.
    expect(_resolve('cambios', presentations: presentations), isNull);
  });

  test('normalization folds accents and punctuation', () {
    expect(normalizePublicCatalogText('Transmisión / Cambios'), 'transmision cambios');
  });
}
