import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/catalog_filter_rail_policy.dart';
import 'package:vinabike_erp/shared/models/public_product_visibility_policy.dart';

/// Guards the composition of the public catalog's left rail.
///
/// Two rules coexist here and each has a failure mode this test pins:
///
///  1. The stored `availability` facet keeps its stored meaning — a visitor
///     stock filter. It is suppressed only when the public stock policy makes
///     it inert (`available_only` ⇒ the catalog is in-stock by definition),
///     and editors still see it disabled with the reason. It must never be
///     silently repurposed into a different control.
///  2. The collection navigator (subcategories, or siblings on a leaf) is
///     page-owned presentation accompanying the category facet — it is NOT a
///     persisted facet key and needs no editor round-trip.
void main() {
  final source = File('lib/public_store/pages/product_catalog_page.dart')
      .readAsStringSync();

  group('public catalog filter rail', () {
    test('availability behavior follows stock policy and editor mode', () {
      expect(
        decideCatalogAvailabilityFacet(
          stockPolicy: PublicCatalogStockPolicy.availableOnly,
          isEditMode: false,
          facetDataAvailable: true,
        ).visible,
        isFalse,
      );

      final editor = decideCatalogAvailabilityFacet(
        stockPolicy: PublicCatalogStockPolicy.availableOnly,
        isEditMode: true,
        facetDataAvailable: true,
      );
      expect(editor.visible, isTrue);
      expect(editor.enabled, isFalse);

      final visitor = decideCatalogAvailabilityFacet(
        stockPolicy: PublicCatalogStockPolicy.all,
        isEditMode: false,
        facetDataAvailable: true,
      );
      expect(visitor.visible, isTrue);
      expect(visitor.enabled, isTrue);
    });

    test('collection behavior chooses children, useful siblings, or nothing',
        () {
      final branch = decideCatalogCollectionFacet<String>(
        selectedId: 'branch',
        children: const ['leaf-a', 'leaf-b'],
        parentName: 'Root',
        siblings: const ['branch', 'other'],
      );
      expect(branch?.heading, 'Subcategorías');
      expect(branch?.options, ['leaf-a', 'leaf-b']);
      expect(branch?.siblingMode, isFalse);

      final leaf = decideCatalogCollectionFacet<String>(
        selectedId: 'leaf-a',
        children: const [],
        parentName: 'Transmisión',
        siblings: const ['leaf-a', 'leaf-b'],
      );
      expect(leaf?.heading, 'Más en Transmisión');
      expect(leaf?.siblingMode, isTrue);

      expect(
        decideCatalogCollectionFacet<String>(
          selectedId: null,
          children: const [],
          parentName: null,
          siblings: const [],
        ),
        isNull,
      );
      expect(
        decideCatalogCollectionFacet<String>(
          selectedId: 'only-leaf',
          children: const [],
          parentName: 'Solo',
          siblings: const ['only-leaf'],
        ),
        isNull,
      );
    });

    test('the stored availability key renders the availability filter', () {
      expect(
        source,
        contains(
          'WebsiteCatalogFacet.availability =>\n'
          '          _buildAvailabilityFacet(refreshPanel)',
        ),
      );
      expect(source, contains("'Sólo productos disponibles'"));
    });

    test(
        'the filter is suppressed for visitors only when the policy makes '
        'it inert', () {
      expect(
        source,
        contains('decideCatalogAvailabilityFacet('),
      );
      expect(
        source,
        contains('if (!decision.visible)'),
      );
      // Editors keep a disabled, explained control instead of a vanished one.
      expect(
        source,
        contains(
          'Se está usando la regla pública de stock configurada para el sitio.',
        ),
      );
    });

    test('the collection navigator is page-owned, not a persisted facet', () {
      expect(
        source,
        contains('if (facet == WebsiteCatalogFacet.categories) {'),
      );
      expect(
        source,
        contains('addSection(_buildCollectionNavigatorFacet());'),
      );
      // It must not be wired to any stored facet key.
      expect(
        source,
        isNot(
          contains(
            'WebsiteCatalogFacet.availability => '
            '_buildCollectionNavigatorFacet()',
          ),
        ),
      );
    });

    test('a leaf collection offers its siblings rather than nothing', () {
      expect(source, contains('decideCatalogCollectionFacet<_CategoryNode>('));
      expect(source, contains('parentName: parent?.name'));
    });

    test('the catalog root keeps the navigator quiet', () {
      // `Categorías` already lists the entry points; repeating them is noise.
      expect(
        source,
        contains('if (selectedId == null) return const SizedBox.shrink();'),
      );
    });

    test('navigation options stay published, non-empty and touch-sized', () {
      expect(source, contains('List<_CategoryNode> _navigableChildren('));
      expect(source, contains('child.isPublished &&'));
      expect(source, contains('_countProductsInCategoryTree(child, null) > 0'));
      // Compact hosts render this same rail inside the filter sheet.
      expect(source, contains('minHeight: 48'));
    });
  });
}
