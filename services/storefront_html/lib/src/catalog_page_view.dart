import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_public_core/public_store/models/public_catalog_facets.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

import 'catalog_page_model.dart';
import 'product_card.dart';
import 'site_layout.dart';

/// `/productos`, a category or a search, laid out like the Flutter catalog
/// (`product_catalog_page.dart`, `catalog_collection_presentation.dart`).
/// Filters are GET forms and links, so the page works without JavaScript; the
/// page script only applies a checkbox or an order as soon as it changes.
Component catalogPageDocument(CatalogPageModel page) => sitePage(
  context: page.page,
  meta: page.meta,
  content: [
    if (page.categoryId != null) ...[
      _Hero(page),
      if (page.subcategories.isNotEmpty) _Subcategories(page),
    ],
    div(classes: 'wrap catalog', [_Filters(page), _Results(page)]),
  ],
);

/// A category URL that is unknown or not published: the Flutter catalog's
/// «Esta colección no está disponible», answered with a 404.
Component unavailableCategoryDocument(PageContext context) => sitePage(
  context: context,
  meta: PageMeta(
    title: 'Colección no disponible · ${context.shell.storeName}',
    description: 'Esta colección no está disponible.',
    canonicalUrl: '${context.storeUrl}/productos',
    indexable: false,
  ),
  content: [
    div(classes: 'wrap notfound', [
      h1([.text('Esta colección no está disponible')]),
      p([
        .text(
          'La categoría puede haber cambiado de ruta, estar fuera de la '
          'navegación pública o ya no existir.',
        ),
      ]),
      a(classes: 'primary-link', href: '/productos', [
        .text('Ver todos los productos'),
      ]),
    ]),
  ],
);

class _Hero extends StatelessComponent {
  const _Hero(this.page);

  final CatalogPageModel page;

  @override
  Component build(BuildContext context) {
    final look = page.presentation;
    // Flutter draws the band at half the editor's desktop height, and on a
    // phone at 72 % of that, never above 180.
    final height = (look.heroSize.desktopHeight * 0.5).round();
    final phone = (height * 0.72).clamp(0, 180).round();
    return section(
      classes: look.heroAlignment == WebsiteCatalogHeroAlignment.center
          ? 'hero center'
          : 'hero',
      attributes: {
        'style':
            '--hero:${height}px;--hero-phone:${phone}px;'
            '--shade:${look.heroOverlay.toStringAsFixed(2)}',
      },
      [
        if (page.heroImage.isNotEmpty)
          img(
            src: page.heroImage,
            alt: '',
            attributes: {'fetchpriority': 'high', 'decoding': 'async'},
          ),
        div(classes: 'wrap', [
          div(classes: 'hero-text', [
            if (look.heroEyebrow.trim().isNotEmpty)
              p(classes: 'eyebrow', [.text(look.heroEyebrow.trim())]),
            h1([.text(page.displayTitle)]),
            if (page.intro.isNotEmpty)
              p(classes: 'hero-intro', [.text(page.intro)]),
          ]),
        ]),
      ],
    );
  }
}

class _Subcategories extends StatelessComponent {
  const _Subcategories(this.page);

  final CatalogPageModel page;

  @override
  Component build(BuildContext context) => nav(
    classes: 'subcats',
    attributes: {'aria-label': 'Subcategorías'},
    [
      div(classes: 'wrap', [
        ul([
          for (final child in page.subcategories)
            li([
              a(href: child.path, [.text(child.label)]),
            ]),
        ]),
      ]),
    ],
  );
}

class _Filters extends StatelessComponent {
  const _Filters(this.page);

  final CatalogPageModel page;

  @override
  Component build(BuildContext context) {
    final q = page.query;
    // The editor's facet order; technical specs follow the brand facet, or
    // close the rail when the presentation shows no brands.
    final sections = <Component>[];
    var specsAdded = false;
    void addSpecs() {
      if (specsAdded) return;
      specsAdded = true;
      sections.addAll(page.specFacets.map(_specFacet));
    }

    for (final facet in page.presentation.facets) {
      switch (facet) {
        case WebsiteCatalogFacet.categories:
          sections.add(_categories());
          if (page.navigator case final decision?) {
            sections.add(
              _categoryLinks(decision.heading, decision.options),
            );
          }
        case WebsiteCatalogFacet.availability:
          if (page.availabilityFacetVisible) sections.add(_availability());
        case WebsiteCatalogFacet.brand:
          if (page.facets.brands.isNotEmpty) sections.add(_brands());
          addSpecs();
        case WebsiteCatalogFacet.price:
          sections.add(_price());
      }
    }
    addSpecs();

    return div(classes: 'filters-panel', [
      // On a phone a checkbox opens the filters without JavaScript.
      Component.element(
        tag: 'input',
        id: 'filtros',
        classes: 'filters-check',
        attributes: {'type': 'checkbox', 'aria-label': 'Mostrar los filtros'},
      ),
      Component.element(
        tag: 'label',
        classes: 'filters-toggle',
        attributes: {'for': 'filtros', 'aria-hidden': 'true'},
        children: [const RawText(_filterIcon), .text('Filtro')],
      ),
      Component.element(
        tag: 'aside',
        classes: 'filters',
        attributes: {'aria-label': 'Filtros'},
        children: [
          p(classes: 'side-title', [.text('Filtros')]),
          form(
            classes: 'search',
            action: page.basePath,
            method: FormMethod.get,
            attributes: {'role': 'search'},
            [
              label(classes: 'sr', attributes: {'for': 'buscar'}, [
                .text('Buscar productos'),
              ]),
              Component.element(
                tag: 'input',
                id: 'buscar',
                attributes: {
                  'type': 'search',
                  'name': 'q',
                  'value': q.searchQuery,
                  'placeholder': 'Buscar productos',
                  'autocomplete': 'off',
                  'enterkeyhint': 'search',
                },
              ),
              ..._keep(q, except: const {'q'}),
            ],
          ),
          // The filters are one form that keeps the search and the order.
          form(
            action: page.basePath,
            method: FormMethod.get,
            attributes: {'data-autosubmit': ''},
            [
              ..._keep(
                q,
                except: const {
                  'brand',
                  'stock',
                  'min_price',
                  'max_price',
                  'spec',
                },
              ),
              ...sections,
              button(
                classes: 'apply',
                attributes: {'type': 'submit'},
                [.text('Aplicar filtros')],
              ),
            ],
          ),
        ],
      ),
    ]);
  }

  Component _categories() {
    final open = page.openBranch;
    Component node(String id, int depth) {
      final link = page.linkTo(id);
      final children = open.contains(id)
          ? page.visibleChildren(id)
          : const <String>[];
      return li([
        a(
          href: link.path,
          attributes: {
            if (page.categoryId == id) 'aria-current': 'page',
            if (depth > 0) 'style': 'padding-left:${depth * 14}px',
          },
          [
            span([.text(link.label)]),
            span(classes: 'n', [.text('${link.count}')]),
          ],
        ),
        if (children.isNotEmpty)
          ul([for (final child in children) node(child, depth + 1)]),
      ]);
    }

    return section(classes: 'facet', [
      h2([.text('Categorías')]),
      ul([
        li([
          a(
            href: '/productos',
            attributes: {if (page.categoryId == null) 'aria-current': 'page'},
            [
              span([.text('Todas')]),
              span(classes: 'n', [.text('${page.allCount}')]),
            ],
          ),
        ]),
        for (final root in page.rootCategories) node(root, 0),
      ]),
    ]);
  }

  Component _categoryLinks(String heading, List<String> ids) =>
      section(classes: 'facet', [
        h2([.text(heading)]),
        ul([
          for (final link in ids.map(page.linkTo))
            li([
              a(
                href: link.path,
                attributes: {
                  if (page.categoryId == link.id) 'aria-current': 'page',
                },
                [
                  span([.text(link.label)]),
                  span(classes: 'n', [.text('${link.count}')]),
                ],
              ),
            ]),
        ]),
      ]);

  Component _availability() => section(classes: 'facet', [
    h2([.text('Disponibilidad')]),
    label([
      span([
        _checkbox(
          'stock',
          WebsiteCatalogStockFilter.available.storageValue,
          page.query.stock == WebsiteCatalogStockFilter.available,
        ),
        .text('Sólo productos disponibles'),
      ]),
    ]),
  ]);

  Component _brands() {
    final selected = page.query.brandIds.toSet();
    return section(classes: 'facet', [
      h2([.text('Marca')]),
      ul([
        for (final brand in page.facets.brands)
          li([
            label([
              span([
                _checkbox('brand', brand.id, selected.contains(brand.id)),
                .text(brand.label),
              ]),
              span(classes: 'n', [.text('${brand.itemCount}')]),
            ]),
          ]),
      ]),
    ]);
  }

  Component _specFacet(PublicCatalogSpecFacet facet) {
    final selected =
        page.query.specFilters[facet.key]?.toSet() ?? const <String>{};
    String labelOf(String value) => page.specValueLabel(facet, value);
    return section(classes: 'facet', [
      h2([.text(facet.label)]),
      ul([
        for (final value in orderedPublicSpecFacetValues(
          facet,
          selected: selected,
          labelOf: labelOf,
        ))
          li([
            label([
              span([
                _checkbox(
                  '${WebsiteCatalogQuery.specParameterPrefix}${facet.key}',
                  value.value,
                  selected.contains(value.value),
                ),
                .text(labelOf(value.value)),
              ]),
              span(classes: 'n', [.text('${value.itemCount}')]),
            ]),
          ]),
      ]),
    ]);
  }

  Component _price() {
    final q = page.query;
    final facets = page.facets;
    return section(classes: 'facet price-facet', [
      h2([.text('Precio')]),
      if (facets.minPrice != null && facets.maxPrice != null)
        p(classes: 'n', [
          .text(
            '${ChileanUtils.formatCurrency(facets.minPrice!)} – '
            '${ChileanUtils.formatCurrency(facets.maxPrice!)}',
          ),
        ]),
      div(classes: 'price-range', [
        _priceInput('min_price', 'Mínimo', q.minPrice),
        _priceInput('max_price', 'Máximo', q.maxPrice),
      ]),
      // Typing a price never sends the form by itself: it waits for this.
      button(
        classes: 'apply-now',
        attributes: {'type': 'submit'},
        [.text('Aplicar')],
      ),
    ]);
  }

  static Component _priceInput(String name, String text, double? value) =>
      label([
        span(classes: 'price-label', [.text(text)]),
        Component.element(
          tag: 'input',
          attributes: {
            'type': 'number',
            'name': name,
            'min': '0',
            'step': '1',
            'inputmode': 'numeric',
            'data-manual': '',
            if (value != null) 'value': value.toStringAsFixed(0),
          },
        ),
      ]);

  static Component _checkbox(String name, String value, bool checked) =>
      Component.element(
        tag: 'input',
        attributes: {
          'type': 'checkbox',
          'name': name,
          'value': value,
          if (checked) 'checked': '',
        },
      );
}

/// Hidden inputs that carry the rest of the URL's query through a form,
/// leaving out the page (a new filter starts again on page 1) and [except].
/// `spec` in [except] drops every `spec.<key>`.
List<Component> _keep(WebsiteCatalogQuery query, {required Set<String> except}) {
  final kept = <Component>[];
  for (final entry in query.toQueryParameters().entries) {
    if (entry.key == 'page') continue;
    if (except.contains(entry.key)) continue;
    if (except.contains('spec') &&
        entry.key.startsWith(WebsiteCatalogQuery.specParameterPrefix)) {
      continue;
    }
    kept.add(
      Component.element(
        tag: 'input',
        attributes: {'type': 'hidden', 'name': entry.key, 'value': entry.value},
      ),
    );
  }
  return kept;
}

class _Results extends StatelessComponent {
  const _Results(this.page);

  final CatalogPageModel page;

  @override
  Component build(BuildContext context) {
    final q = page.query;
    final first = (page.currentPage - 1) * q.pageSize + 1;
    final last = (page.currentPage * q.pageSize).clamp(0, page.total);
    final pageSizes = {20, 50, 100, q.pageSize}.toList()..sort();
    return section(classes: 'results', attributes: {'aria-label': 'Productos'}, [
      div(classes: 'results-head', [
        _heading(),
        form(
          classes: 'order',
          action: page.basePath,
          method: FormMethod.get,
          attributes: {'data-autosubmit': ''},
          [
            ..._keep(q, except: const {'sort', 'page_size'}),
            label([
              .text('Mostrar: '),
              _select('page_size', '${q.pageSize}', [
                for (final size in pageSizes) ('$size', '$size por página'),
              ]),
            ]),
            label([
              .text('Ordenar por: '),
              _select('sort', q.sort.storageValue, const [
                ('name', 'Nombre'),
                ('price_asc', 'Precio ↑'),
                ('price_desc', 'Precio ↓'),
                ('newest', 'Recientes'),
              ]),
            ]),
            button(
              classes: 'apply',
              attributes: {'type': 'submit'},
              [.text('Aplicar')],
            ),
          ],
        ),
      ]),
      if (page.queryError case final error?)
        p(classes: 'notice', attributes: {'role': 'status'}, [.text(error)]),
      p(classes: 'count', [
        .text(
          page.total > 0
              ? 'Mostrando $first - $last de ${page.total} productos'
              : '0 productos encontrados',
        ),
      ]),
      if (q.categoryScope == WebsiteCatalogCategoryScope.direct &&
          page.categoryId != null)
        p(classes: 'scope', [
          strong([.text('Solo ${page.shell.categoryName(page.categoryId!)}')]),
          a(href: _withSubcategories(), [.text('Incluir subcategorías')]),
        ]),
      if (page.products.isEmpty)
        div(classes: 'empty', [
          p(classes: 'empty-title', [.text('No se encontraron productos')]),
          p([.text('Intenta ajustar los filtros de búsqueda')]),
        ])
      else
        ul(
          classes: switch (page.presentation.gridDensity) {
            WebsiteCatalogGridDensity.compact => 'cards compact',
            WebsiteCatalogGridDensity.editorial => 'cards editorial',
            WebsiteCatalogGridDensity.balanced => 'cards',
          },
          [
            for (final (i, product) in page.products.indexed)
              ProductCard(
                commerce: product.commerce,
                path: product.path,
                thumbnail: product.thumbnail,
                sizes: cardImageSizes(page.presentation.gridDensity),
                eager: i < 2,
                first: i == 0,
              ),
          ],
        ),
      if (page.pageCount > 1) _pager(),
    ]);
  }

  /// «PRODUCTOS», or the category's trail when its presentation shows it.
  /// On `/productos` it is the page's title; a category's is in the hero.
  Component _heading() {
    if (page.categoryId == null) {
      return h1(classes: 'trail', [strong([.text('PRODUCTOS')])]);
    }
    if (!page.presentation.showBreadcrumbs) {
      return p(classes: 'trail', [strong([.text('PRODUCTOS')])]);
    }
    return nav(classes: 'trail', attributes: {'aria-label': 'Ruta'}, [
      a(href: '/productos', [.text('Productos')]),
      for (final crumb in page.trail)
        if (crumb.id == page.categoryId)
          strong(attributes: {'aria-current': 'page'}, [.text(crumb.label)])
        else
          a(href: crumb.path, [.text(crumb.label)]),
    ]);
  }

  String _withSubcategories() {
    final q = page.query;
    return page.hrefWith(
      WebsiteCatalogQuery(
        searchQuery: q.searchQuery,
        productType: q.productType,
        brandIds: q.brandIds,
        specFilters: q.specFilters,
        minPrice: q.minPrice,
        maxPrice: q.maxPrice,
        stock: q.stock,
        sort: q.sort,
        pageSize: q.pageSize,
      ),
    );
  }

  Component _pager() {
    final current = page.currentPage;
    final count = page.pageCount;
    final numbers =
        {1, count, current - 1, current, current + 1}
            .where((n) => n >= 1 && n <= count)
            .toList()
          ..sort();
    final items = <Component>[
      if (current > 1)
        a(
          href: page.pageHref(current - 1),
          attributes: {'rel': 'prev', 'aria-label': 'Página anterior'},
          [.text('‹')],
        ),
    ];
    int? previous;
    for (final n in numbers) {
      if (previous != null && n > previous + 1) {
        items.add(span(classes: 'gap', [.text('…')]));
      }
      items.add(
        n == current
            ? span(attributes: {'aria-current': 'page'}, [.text('$n')])
            : a(href: page.pageHref(n), [.text('$n')]),
      );
      previous = n;
    }
    if (current < count) {
      items.add(
        a(
          href: page.pageHref(current + 1),
          attributes: {'rel': 'next', 'aria-label': 'Página siguiente'},
          [.text('›')],
        ),
      );
    }
    return nav(classes: 'pager', attributes: {'aria-label': 'Páginas'}, items);
  }

  static Component _select(
    String name,
    String value,
    List<(String, String)> options,
  ) => Component.element(
    tag: 'select',
    attributes: {'name': name},
    children: [
      for (final (optionValue, text) in options)
        Component.element(
          tag: 'option',
          attributes: {
            'value': optionValue,
            if (optionValue == value) 'selected': '',
          },
          children: [.text(text)],
        ),
    ],
  );
}

const _filterIcon =
    '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">'
    '<path d="M4 7h10M18 7h2M4 17h4M12 17h8" stroke="currentColor" '
    'stroke-width="2" stroke-linecap="round"/><circle cx="16" cy="7" r="2" '
    'fill="none" stroke="currentColor" stroke-width="2"/><circle cx="10" '
    'cy="17" r="2" fill="none" stroke="currentColor" stroke-width="2"/></svg>';
