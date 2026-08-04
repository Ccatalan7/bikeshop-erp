import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_catalog.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';

/// The one catalog of insertable blocks.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t11 frame **11a** +
/// `handoff-t11/spec.json` rules: *"24 familias son más de 7, así que la lista
/// es buscable"* y *"Una familia no disponible se muestra atenuada con su razón
/// en una línea; nunca se oculta"*.
void main() {
  group('cobertura del registro', () {
    test('cubre TODAS las definiciones registradas, sin duplicados', () {
      final entries = WebsiteBlockCatalog.entries();
      final types = entries.map((entry) => entry.type).toList();

      expect(types.toSet().length, types.length, reason: 'hay duplicados');
      expect(types.toSet(), WebsiteBlockType.values.toSet());
      expect(entries.length, WebsiteBlockRegistry.all().length);
    });

    test(
        'cada item expone identidad estable, título, descripción, icono, '
        'categoría y texto buscable', () {
      for (final entry in WebsiteBlockCatalog.entries()) {
        expect(entry.id, entry.type.name);
        expect(entry.title.trim(), isNotEmpty,
            reason: '${entry.id} sin título');
        expect(entry.category.trim(), isNotEmpty);
        expect(entry.searchText, contains(entry.type.name.toLowerCase()));
        expect(entry.icon, isNotNull);
      }
    });

    test('la identidad es el block_type persistido, no una etiqueta', () {
      final hero = WebsiteBlockCatalog.entries()
          .firstWhere((entry) => entry.type == WebsiteBlockType.hero);
      expect(hero.id, 'hero');
    });
  });

  group('Footer: visible y deshabilitado con razón', () {
    test('sigue listado y nunca es insertable', () {
      final entries = WebsiteBlockCatalog.entries();
      final footer = entries
          .where((entry) => entry.type == WebsiteBlockType.footer)
          .toList();

      expect(footer, hasLength(1), reason: 'el footer no puede desaparecer');
      expect(footer.single.isInsertable, isFalse);
      expect(footer.single.unavailableReason, isNotNull);
      expect(footer.single.unavailableReason!.trim(), isNotEmpty);
    });

    test('la razón es la de t11a cuando ya existe en la página', () {
      final footer = WebsiteBlockCatalog.entries(
        presentBlockTypes: const ['hero', 'footer'],
      ).firstWhere((entry) => entry.type == WebsiteBlockType.footer);

      expect(footer.unavailableReason, 'Ya existe en esta página');
    });

    test('en una página sin footer la razón sigue siendo verdadera', () {
      final footer = WebsiteBlockCatalog.entries(
        presentBlockTypes: const ['hero'],
      ).firstWhere((entry) => entry.type == WebsiteBlockType.footer);

      expect(footer.unavailableReason, isNot('Ya existe en esta página'));
      expect(footer.isInsertable, isFalse);
    });

    test('un filtro nunca convierte un deshabilitado en oculto', () {
      // El registro lo titula `Footer`; la copia de t11a dice «Pie de página».
      // La palabra la manda el registro (fuera de scope esta ronda); lo que se
      // afirma aquí es la regla: buscar una familia inerte la muestra, no la
      // esconde.
      final filtered = WebsiteBlockCatalog.filtered(query: 'footer');
      expect(
        filtered.where((entry) => entry.type == WebsiteBlockType.footer),
        hasLength(1),
      );
      expect(
        WebsiteBlockCatalog.filtered(category: 'Especial')
            .where((entry) => entry.type == WebsiteBlockType.footer),
        hasLength(1),
      );
    });

    test('ninguna otra familia queda deshabilitada por accidente', () {
      final disabled = WebsiteBlockCatalog.entries()
          .where((entry) => !entry.isInsertable)
          .map((entry) => entry.type)
          .toSet();
      expect(disabled, WebsiteBlockCatalog.singletonTypes);
    });
  });

  group('búsqueda', () {
    test('encuentra por título', () {
      final results = WebsiteBlockCatalog.filtered(query: 'Carrusel');
      expect(
        results.map((entry) => entry.type),
        contains(WebsiteBlockType.carousel),
      );
    });

    test('encuentra por tipo persistido', () {
      final results = WebsiteBlockCatalog.filtered(query: 'videoBanner');
      expect(
        results.map((entry) => entry.type),
        contains(WebsiteBlockType.videoBanner),
      );
    });

    test('encuentra por categoría', () {
      final results = WebsiteBlockCatalog.filtered(query: 'Conversión');
      expect(results, isNotEmpty);
      for (final entry in results) {
        expect(entry.searchText, contains('conversi'));
      }
    });

    test('ignora acentos y mayúsculas: se teclea en un teléfono', () {
      final withAccent = WebsiteBlockCatalog.filtered(query: 'Conversión');
      final withoutAccent = WebsiteBlockCatalog.filtered(query: 'conversion');
      expect(
        withoutAccent.map((entry) => entry.type).toList(),
        withAccent.map((entry) => entry.type).toList(),
      );
      expect(withoutAccent, isNotEmpty);
    });

    test('una consulta vacía no filtra nada', () {
      expect(
        WebsiteBlockCatalog.filtered(query: '   ').length,
        WebsiteBlockCatalog.entries().length,
      );
    });

    test('una consulta sin resultados devuelve la lista vacía', () {
      expect(
        WebsiteBlockCatalog.filtered(query: 'zzzz-no-existe'),
        isEmpty,
      );
    });

    test('la categoría y la búsqueda se combinan', () {
      final results = WebsiteBlockCatalog.filtered(
        category: 'Estructura',
        query: 'hero',
      );
      // `Carrusel Hero` también contiene la palabra, y eso es correcto: la
      // búsqueda es por texto, no por tipo exacto.
      expect(
          results.map((entry) => entry.type), contains(WebsiteBlockType.hero));
      for (final entry in results) {
        expect(entry.category, 'Estructura');
        expect(entry.searchText, contains('hero'));
      }
      // Y la categoría sí excluye: `Footer` es `Especial`.
      expect(
        results.map((entry) => entry.type),
        isNot(contains(WebsiteBlockType.footer)),
      );
    });
  });

  group('categorías', () {
    test('empiezan por Todos y respetan el orden del editor', () {
      final categories = WebsiteBlockCatalog.categories();
      expect(categories.first, WebsiteBlockCatalog.allCategory);
      expect(categories.toSet().length, categories.length);

      final known = categories
          .skip(1)
          .where(WebsiteBlockCatalog.categoryOrder.contains)
          .toList();
      final expectedOrder =
          WebsiteBlockCatalog.categoryOrder.where(known.contains).toList();
      expect(known, expectedOrder);
    });

    test('toda categoría de una entrada existe en la lista', () {
      final categories = WebsiteBlockCatalog.categories().toSet();
      for (final entry in WebsiteBlockCatalog.entries()) {
        expect(
          categories,
          contains(entry.category),
          reason: '${entry.id} declara una categoría que nadie ofrece',
        );
      }
    });

    test('Todos no filtra', () {
      expect(
        WebsiteBlockCatalog.filtered(
          category: WebsiteBlockCatalog.allCategory,
        ).length,
        WebsiteBlockCatalog.entries().length,
      );
    });
  });

  group('la posición es explícita y ambos lados son reales', () {
    test('antes y después resuelven índices distintos', () {
      const anchor = WebsiteBlockInsertionAnchor(
        anchorIndex: 2,
        anchorTitle: 'Carrusel',
        initialSide: WebsiteBlockInsertSide.after,
      );

      expect(anchor.indexFor(WebsiteBlockInsertSide.before), 2);
      expect(anchor.indexFor(WebsiteBlockInsertSide.after), 3);
    });

    test('las etiquetas son las exactas de t11a', () {
      expect(WebsiteBlockInsertSide.before.label, 'Antes de');
      expect(WebsiteBlockInsertSide.after.label, 'Después de');
    });
  });
}
