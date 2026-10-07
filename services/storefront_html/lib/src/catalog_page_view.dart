import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_public_core/public_store/models/public_catalog_facets.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

import 'catalog_page_model.dart';
import 'material_icons.dart';
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
    div(
      classes: 'wrap catalog',
      attributes: page.pickSection(WebsiteCatalogDraftSection.list),
      [_Filters(page), _Results(page)],
    ),
  ],
);

/// A category URL that is unknown or not published: the Flutter catalog's
/// «Esta colección no está disponible», answered with a 404.
Component unavailableCategoryDocument(
  PageContext context, {
  bool services = false,
}) => sitePage(
  context: context,
  meta: PageMeta(
    title: 'Colección no disponible · ${context.shell.storeName}',
    description: 'Esta colección no está disponible.',
    canonicalUrl:
        '${context.storeUrl}${services ? '/servicios' : '/productos'}',
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
      a(classes: 'primary-link', href: services ? '/servicios' : '/productos', [
        .text(services ? 'Ver todos los servicios' : 'Ver todos los productos'),
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
        ...page.pickSection(WebsiteCatalogDraftSection.hero),
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
    // The URL parameters a control below sends. Any other active filter rides
    // along hidden: a control that is not drawn (every brand and spec when
    // the facet read failed, or a brand whose name is unknown) must not drop
    // it.
    final controlled = <String>{};
    // The brands that are checkboxes below; a brand of the URL whose name
    // is unknown is not one, and rides along hidden on its own.
    final drawnBrands = <String>{};
    var specsAdded = false;
    void addSpecs() {
      if (specsAdded) return;
      specsAdded = true;
      for (final facet in page.specFacets) {
        controlled.add(
          '${WebsiteCatalogQuery.specParameterPrefix}${facet.key}',
        );
        sections.add(_specFacet(facet));
      }
    }

    for (final facet in page.presentation.facets) {
      switch (facet) {
        case WebsiteCatalogFacet.categories:
          sections.add(_categories());
          if (page.navigator case final decision?) {
            sections.add(_categoryLinks(decision.heading, decision.options));
          }
        case WebsiteCatalogFacet.availability:
          if (page.availabilityFacetVisible) {
            controlled.add('stock');
            sections.add(_availability());
          }
        case WebsiteCatalogFacet.brand:
          final brands = page.brandOptions;
          if (brands.isNotEmpty) {
            controlled.add('brand');
            drawnBrands.addAll([for (final brand in brands) brand.id]);
            sections.add(_brands(brands));
          }
          addSpecs();
        case WebsiteCatalogFacet.price:
          controlled.addAll(const {'min_price', 'max_price'});
          sections.add(_price());
      }
    }
    addSpecs();

    // A rail on a wide page; on a phone, the «Filtro» sheet that `#filtros`
    // (in the results bar) opens without JavaScript.
    return div(classes: 'filters-panel', [
      Component.element(
        tag: 'aside',
        classes: 'filters sheet-panel',
        attributes: {'aria-label': 'Filtros'},
        children: [
          div(classes: 'sheet-head', [
            span(classes: 'grab', []),
            p(classes: 'side-title', [.text('Filtros')]),
            _closeSheet('filtros', 'Cerrar los filtros'),
          ]),
          div(classes: 'sheet-body', [
            form(
              classes: 'search',
              action: page.basePath,
              method: FormMethod.get,
              attributes: {'role': 'search'},
              [
                label(
                  classes: 'sr',
                  attributes: {'for': 'buscar'},
                  [.text('Buscar ${page.noun}')],
                ),
                Component.element(
                  tag: 'input',
                  id: 'buscar',
                  attributes: {
                    'type': 'search',
                    'name': 'q',
                    'value': q.searchQuery,
                    'placeholder': 'Buscar ${page.noun}',
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
                ..._keep(q, except: controlled),
                for (final id in q.brandIds)
                  if (controlled.contains('brand') && !drawnBrands.contains(id))
                    Component.element(
                      tag: 'input',
                      attributes: {
                        'type': 'hidden',
                        'name': 'brand',
                        'value': id,
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
          ]),
        ],
      ),
      _sheetScrim('filtros'),
    ]);
  }

  /// Flutter's category tree: a radio per row, «Nombre (n)», and a chevron
  /// that opens a branch without leaving the page. The current branch is
  /// open.
  Component _categories() {
    final open = page.openBranch;
    var toggles = 0;
    Component node(String id, int depth) {
      final link = page.linkTo(id);
      final children = page.visibleChildren(id);
      final toggle = 'rama-${++toggles}';
      return li([
        if (children.isNotEmpty)
          Component.element(
            tag: 'input',
            id: toggle,
            classes: 'branch',
            attributes: {
              'type': 'checkbox',
              'aria-label': 'Subcategorías de ${link.label}',
              'data-manual': '',
              if (open.contains(id)) 'checked': '',
            },
          ),
        _categoryRow(
          href: link.path,
          text: page.countsKnown ? '${link.label} (${link.count})' : link.label,
          current: page.categoryId == id,
          depth: depth,
          toggle: children.isEmpty ? null : toggle,
        ),
        if (children.isNotEmpty)
          ul([for (final child in children) node(child, depth + 1)]),
      ]);
    }

    return section(classes: 'facet', [
      h2([.text('Categorías')]),
      ul(classes: 'tree', [
        li(classes: 'all', [
          _categoryRow(
            href: page.rootPath,
            text: page.countsKnown ? 'Todas (${page.allCount})' : 'Todas',
            current: page.categoryId == null,
            depth: 0,
          ),
        ]),
        for (final root in page.rootCategories) node(root, 0),
      ]),
    ]);
  }

  static Component _categoryRow({
    required String href,
    required String text,
    required bool current,
    required int depth,
    String? toggle,
  }) => div(
    classes: 'row',
    attributes: {if (depth > 0) 'style': 'padding-left:${depth * 16}px'},
    [
      if (toggle != null)
        Component.element(
          tag: 'label',
          classes: 'chev',
          attributes: {'for': toggle, 'aria-hidden': 'true'},
          children: [RawText(materialIcon(mdChevronRightSharp, size: 18))],
        )
      else
        span(classes: 'chev', []),
      a(
        href: href,
        attributes: {if (current) 'aria-current': 'page'},
        [
          span(classes: 'radio', [
            if (current) RawText(materialIcon(mdCheck, size: 12)),
          ]),
          span([.text(text)]),
        ],
      ),
    ],
  );

  /// «Subcategorías» or «Más en `padre`»: where to go from here, with a
  /// chevron where the branch goes deeper.
  Component _categoryLinks(String heading, List<String> ids) =>
      section(classes: 'facet', [
        h2([.text(heading)]),
        ul(classes: 'onward', [
          for (final link in ids.map(page.linkTo))
            li([
              a(
                href: link.path,
                attributes: {
                  if (page.categoryId == link.id) 'aria-current': 'page',
                },
                [
                  span([.text(link.label)]),
                  if (page.countsKnown)
                    span(classes: 'n', [.text('${link.count}')])
                  else
                    span(classes: 'n', []),
                  if (page.visibleChildren(link.id).isNotEmpty)
                    RawText(materialIcon(mdChevronRight, size: 16))
                  else
                    span(classes: 'go-gap', []),
                ],
              ),
            ]),
        ]),
      ]);

  Component _availability() => section(classes: 'facet', [
    h2(classes: 'with-info', [
      .text('Disponibilidad'),
      span(
        classes: 'info',
        attributes: {
          'title':
              'Filtra adicionalmente el catálogo público. Nunca puede mostrar '
              'productos que las reglas del sitio ya ocultan.',
        },
        [RawText(materialIcon(mdInfoOutline, size: 16))],
      ),
    ]),
    _checkRow(
      name: 'stock',
      value: WebsiteCatalogStockFilter.available.storageValue,
      checked: page.query.stock == WebsiteCatalogStockFilter.available,
      text: 'Sólo productos disponibles',
      strong: true,
    ),
  ]);

  /// Selected brands first, then by name; eight, and the rest behind «Ver N
  /// marcas más».
  Component _brands(List<PublicCatalogBrandFacet> options) {
    final selected = page.query.brandIds.toSet();
    final brands = [...options]
      ..sort((left, right) {
        final leftSelected = selected.contains(left.id);
        if (leftSelected != selected.contains(right.id)) {
          return leftSelected ? -1 : 1;
        }
        return left.label.toLowerCase().compareTo(right.label.toLowerCase());
      });
    final rows = [
      for (final brand in brands)
        _checkRow(
          name: 'brand',
          value: brand.id,
          checked: selected.contains(brand.id),
          text: brand.label,
          count: brand.itemCount,
        ),
    ];
    return section(classes: 'facet', [
      h2([.text('Marca')]),
      ..._firstAndMore(rows, 8, 'marca-mas', 'marcas'),
    ]);
  }

  Component _specFacet(PublicCatalogSpecFacet facet) {
    final selected =
        page.query.specFilters[facet.key]?.toSet() ?? const <String>{};
    String labelOf(String value) => page.specValueLabel(facet, value);
    final rows = [
      for (final value in orderedPublicSpecFacetValues(
        facet,
        selected: selected,
        labelOf: labelOf,
      ))
        _checkRow(
          name: '${WebsiteCatalogQuery.specParameterPrefix}${facet.key}',
          value: value.value,
          checked: selected.contains(value.value),
          text: labelOf(value.value),
          count: value.itemCount,
        ),
    ];
    return section(classes: 'facet', [
      h2([.text(facet.label)]),
      ..._firstAndMore(rows, 6, 'mas-${facet.key}', 'opciones'),
    ]);
  }

  /// [shown] rows, and the rest behind «Ver N `noun` más» / «Mostrar menos».
  static List<Component> _firstAndMore(
    List<Component> rows,
    int shown,
    String id,
    String noun,
  ) {
    if (rows.length <= shown) return rows;
    final toggle = 'ver-$id';
    return [
      ...rows.take(shown),
      Component.element(
        tag: 'input',
        id: toggle,
        classes: 'more-check',
        attributes: {
          'type': 'checkbox',
          'data-manual': '',
          'aria-label': 'Ver ${rows.length - shown} $noun más',
        },
      ),
      div(classes: 'more-rows', rows.skip(shown).toList()),
      Component.element(
        tag: 'label',
        classes: 'more',
        attributes: {'for': toggle, 'aria-hidden': 'true'},
        children: [
          span(classes: 'when-closed', [
            .text('Ver ${rows.length - shown} $noun más'),
          ]),
          span(classes: 'when-open', [.text('Mostrar menos')]),
        ],
      ),
    ];
  }

  Component _price() {
    final q = page.query;
    final facets = page.facets;
    return section(classes: 'facet price-facet', [
      h2([.text('Precio')]),
      if (facets.minPrice != null && facets.maxPrice != null)
        p(classes: 'range', [
          .text(
            '${ChileanUtils.formatCurrency(facets.minPrice!)} – '
            '${ChileanUtils.formatCurrency(facets.maxPrice!)}',
          ),
        ]),
      div(classes: 'price-range', [
        _priceInput('min_price', 'Mínimo', q.minPrice),
        _priceInput('max_price', 'Máximo', q.maxPrice),
      ]),
      div(classes: 'price-actions', [
        // Typing a price never sends the form by itself: it waits for this.
        button(
          classes: 'apply-now',
          attributes: {'type': 'submit'},
          [.text('Aplicar')],
        ),
        if (q.minPrice != null || q.maxPrice != null)
          a(
            classes: 'price-clear',
            href: page.priceClearedHref,
            attributes: {'title': 'Quitar rango de precio'},
            [
              RawText(materialIcon(mdClose, size: 18)),
              span(classes: 'sr', [.text('Quitar rango de precio')]),
            ],
          ),
      ]),
    ]);
  }

  /// An outlined field whose label rises onto the border when it has a
  /// value, with the «$ » prefix, as Flutter's dense `OutlineInputBorder`.
  static Component _priceInput(String name, String text, double? value) =>
      label(classes: 'field', [
        Component.element(
          tag: 'input',
          attributes: {
            'type': 'number',
            'name': name,
            'min': '0',
            'step': '1',
            'inputmode': 'numeric',
            'placeholder': ' ',
            'data-manual': '',
            if (value != null) 'value': value.toStringAsFixed(0),
          },
        ),
        span(classes: 'field-label', [.text(text)]),
        span(
          classes: 'field-prefix',
          attributes: {'aria-hidden': 'true'},
          [.text(r'$')],
        ),
      ]);

  static Component _checkRow({
    required String name,
    required String value,
    required bool checked,
    required String text,
    int? count,
    bool strong = false,
  }) => label(classes: strong ? 'check strong' : 'check', [
    Component.element(
      tag: 'input',
      attributes: {
        'type': 'checkbox',
        'name': name,
        'value': value,
        if (checked) 'checked': '',
      },
    ),
    span(classes: 'check-text', [.text(text)]),
    if (count != null) span(classes: 'n', [.text('$count')]),
  ]);
}

/// The ✕ of a phone sheet: it unchecks the sheet's checkbox.
Component _closeSheet(String target, String text) => Component.element(
  tag: 'label',
  classes: 'sheet-close',
  attributes: {'for': target, 'title': 'Cerrar'},
  children: [
    RawText(materialIcon(mdClose)),
    span(classes: 'sr', [.text(text)]),
  ],
);

/// The dimmed page behind a phone sheet; a tap on it closes the sheet.
Component _sheetScrim(String target) => Component.element(
  tag: 'label',
  classes: 'sheet-dim',
  attributes: {'for': target, 'aria-hidden': 'true'},
);

/// Hidden inputs that carry the rest of the URL's query through a form,
/// leaving out the page (a new filter starts again on page 1) and [except]
/// (parameter names, a `spec.<key>` one by one; `spec` drops them all).
List<Component> _keep(
  WebsiteCatalogQuery query, {
  required Set<String> except,
}) {
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

  static const _sorts = [
    (WebsiteCatalogSort.name, 'Nombre', 'Nombre'),
    (WebsiteCatalogSort.priceAsc, 'Precio ↑', 'Precio, menor a mayor'),
    (WebsiteCatalogSort.priceDesc, 'Precio ↓', 'Precio, mayor a menor'),
    (WebsiteCatalogSort.newest, 'Recientes', 'Más recientes'),
  ];

  @override
  Component build(BuildContext context) {
    final q = page.query;
    final first = (page.currentPage - 1) * q.pageSize + 1;
    final last = (page.currentPage * q.pageSize).clamp(0, page.total);
    final pageSizes = {20, 50, 100, q.pageSize}.toList()..sort();
    return section(
      classes: 'results',
      attributes: {'aria-label': page.rootLabel},
      [
        div(classes: 'results-head', [
          _heading(),
          div(classes: 'controls', [
            // A phone's bar: «Filtro» and «Ordenar por» open their sheets.
            _sheetToggle('filtros', 'Mostrar los filtros'),
            Component.element(
              tag: 'label',
              classes: 'bar-button',
              attributes: {'for': 'filtros', 'aria-hidden': 'true'},
              children: [
                RawText(materialIcon(mdTune, size: 20)),
                .text('Filtro'),
              ],
            ),
            _sheetToggle('orden', 'Ordenar los ${page.noun}'),
            Component.element(
              tag: 'label',
              classes: 'bar-button',
              attributes: {'for': 'orden', 'aria-hidden': 'true'},
              children: [
                .text('Ordenar por'),
                RawText(materialIcon(mdKeyboardArrowDown, size: 20)),
              ],
            ),
            form(
              classes: 'order',
              action: page.basePath,
              method: FormMethod.get,
              attributes: {'data-autosubmit': ''},
              [
                ..._keep(q, except: const {'sort', 'page_size'}),
                label([
                  span([.text('Mostrar:')]),
                  _select('page_size', '${q.pageSize}', [
                    for (final size in pageSizes) ('$size', '$size por página'),
                  ]),
                ]),
                label([
                  span([.text('Ordenar por:')]),
                  _select('sort', q.sort.storageValue, [
                    for (final (sort, short, _) in _sorts)
                      (sort.storageValue, short),
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
          p(classes: 'count', [
            if (page.total > 0) ...[
              span(classes: 'wide', [
                .text('Mostrando $first - $last de ${page.total} ${page.noun}'),
              ]),
              span(classes: 'narrow', [.text('${page.total} ${page.noun}')]),
            ] else
              .text('0 ${page.noun} encontrados'),
          ]),
          if (q.categoryScope == WebsiteCatalogCategoryScope.direct &&
              page.categoryId != null)
            p(classes: 'scope', [
              strong([
                .text('Solo ${page.shell.categoryName(page.categoryId!)}'),
              ]),
              a(href: _withSubcategories(), [.text('Incluir subcategorías')]),
            ]),
        ]),
        div(classes: 'sort-sheet sheet-panel', [
          div(classes: 'sheet-head', [
            span(classes: 'grab', []),
            p(classes: 'side-title', [.text('Ordenar por')]),
            _closeSheet('orden', 'Cerrar el orden'),
          ]),
          ul([
            for (final (sort, _, long) in _sorts)
              li([
                a(
                  href: page.sortHref(sort),
                  attributes: {if (sort == q.sort) 'aria-current': 'true'},
                  [
                    span([.text(long)]),
                    if (sort == q.sort) RawText(materialIcon(mdCheck)),
                  ],
                ),
              ]),
          ]),
        ]),
        _sheetScrim('orden'),
        if (page.queryError case final error?)
          p(classes: 'notice', attributes: {'role': 'status'}, [.text(error)]),
        if (page.products.isEmpty)
          div(classes: 'empty', [
            RawText(materialIcon(mdInventory, size: 48)),
            p(classes: 'empty-title', [
              .text('No se encontraron ${page.noun}'),
            ]),
            p([.text('Intenta ajustar los filtros de búsqueda')]),
            if (page.hasFilters)
              a(classes: 'empty-clear', href: page.filtersClearedHref, [
                .text('Quitar los filtros'),
              ]),
          ])
        else
          div(classes: 'cards-box', [
            ul(
              classes: switch (page.presentation.gridDensity) {
                WebsiteCatalogGridDensity.compact => 'cards compact',
                WebsiteCatalogGridDensity.editorial => 'cards editorial',
                WebsiteCatalogGridDensity.balanced => 'cards',
              },
              attributes: measuredList(
                page.categoryId ?? (page.services ? 'servicios' : 'productos'),
                page.displayTitle,
              ),
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
          ]),
        if (page.pageCount > 1) _pager(),
      ],
    );
  }

  static Component _sheetToggle(String id, String text) => Component.element(
    tag: 'input',
    id: id,
    classes: 'sheet-check',
    attributes: {
      'type': 'checkbox',
      'aria-label': text,
      'autocomplete': 'off',
      'data-manual': '',
    },
  );

  /// «PRODUCTOS» («SERVICIOS»), or the category's trail when its
  /// presentation shows it. On the root it is the page's title; a
  /// category's is in the hero.
  Component _heading() {
    final title = page.rootLabel.toUpperCase();
    if (page.categoryId == null) {
      return h1(classes: 'trail', [.text(title)]);
    }
    if (!page.presentation.showBreadcrumbs) {
      return p(classes: 'trail', [.text(title)]);
    }
    return nav(
      classes: 'trail',
      attributes: {'aria-label': 'Ruta'},
      [
        a(href: page.rootPath, [.text(page.rootLabel)]),
        for (final crumb in page.trail)
          if (crumb.id == page.categoryId)
            strong(attributes: {'aria-current': 'page'}, [.text(crumb.label)])
          else
            a(href: crumb.path, [.text(crumb.label)]),
      ],
    );
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

  /// Flutter's pager: «Anterior», the first and last pages, the current one
  /// with its neighbours (1 2 3 near the start, the last three near the end)
  /// and «Siguiente».
  Component _pager() {
    final current = page.currentPage;
    final count = page.pageCount;
    final numbers = {
      1,
      count,
      for (var n = current - 1; n <= current + 1; n++)
        if (n >= 1 && n <= count) n,
      if (current <= 3) ...[2, 3].where((n) => n <= count),
      if (current >= count - 2) ...[count - 2, count - 1].where((n) => n >= 1),
    }.toList()..sort();
    final items = <Component>[
      if (current > 1)
        a(
          classes: 'step',
          href: page.pageHref(current - 1),
          attributes: {'rel': 'prev', 'aria-label': 'Página anterior'},
          [
            RawText(materialIcon(mdChevronLeft, size: 20)),
            span([.text('Anterior')]),
          ],
        )
      else
        span(classes: 'step-gap', []),
    ];
    int? previous;
    for (final n in numbers) {
      if (previous != null && n > previous + 1) {
        items.add(span(classes: 'gap', [.text('...')]));
      }
      items.add(
        n == current
            ? span(
                classes: 'num',
                attributes: {'aria-current': 'page'},
                [.text('$n')],
              )
            : a(classes: 'num', href: page.pageHref(n), [.text('$n')]),
      );
      previous = n;
    }
    items.add(
      current < count
          ? a(
              classes: 'step',
              href: page.pageHref(current + 1),
              attributes: {'rel': 'next', 'aria-label': 'Página siguiente'},
              [
                span([.text('Siguiente')]),
                RawText(materialIcon(mdChevronRightSharp, size: 20)),
              ],
            )
          : span(classes: 'step-gap', []),
    );
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
