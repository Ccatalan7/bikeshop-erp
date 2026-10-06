import 'dart:math' as math;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_models.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/services/mega_menu_presentation.dart';
import 'package:vinabike_public_core/public_store/theme/public_header_contrast.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_color_value.dart';

import 'css_values.dart';
import 'material_icons.dart';
import 'storefront_shell.dart';

/// The desktop header's menu with children, as `public_store_layout.dart`
/// draws it over the desktop projection (`StorefrontShell.menuFor`): an item
/// whose «Clase CSS» has `megamenu` opens the wide panel (`MegaMenuButton`
/// in `lib/public_store/widgets/mega_menu.dart`), any other opens the compact
/// list (`NavigationDropdownButton`). Both triggers are buttons, as Flutter's:
/// the item's own page is «VER TODO» inside. The panel's links are in the
/// HTML from the start, so a crawler follows them without the script.
///
/// The phone and tablet never get here: below 1.080 px the header shows the
/// sheet (`PublicStoreHeaderGeometry`), so the panel's compact layout (under
/// 820 px) is not drawn.
class HeaderMenuColors {
  HeaderMenuColors._({
    required this.surface,
    required this.surfaceLight,
    required this.panelForeground,
    required this.rail,
    required this.railForeground,
  });

  /// `header_menu_surface_color` (black by default; transparent means the
  /// theme's surface) and `header_menu_rail_color` (`PublicStoreTheme
  /// .secondaryGray`), opaque, with white or the theme's text over each by
  /// the shared contrast rule.
  factory HeaderMenuColors.of(StorefrontShell shell, WebsiteThemeRoles roles) {
    int read(String key, int fallback) =>
        parseWebsiteThemeColorValue(shell.setting(key)) ?? fallback;
    int opaque(int argb) => 0xFF000000 | (argb & 0xFFFFFF);
    final configured = read('header_menu_surface_color', 0xFF000000);
    final surface = (configured >> 24) / 255 <= 0.01
        ? roles.background.withAlpha(1)
        : WebsiteRgba.fromArgb(opaque(configured));
    final rail = opaque(read('header_menu_rail_color', 0xFF64748B));
    bool light(int argb) => PublicHeaderContrastMode.automatic
        .usesLightForegroundOn(isOverlay: false, backgroundArgb: argb);
    final surfaceLight = light(_argb(surface));
    return HeaderMenuColors._(
      surface: surface,
      surfaceLight: surfaceLight,
      panelForeground: surfaceLight ? WebsiteRgba.white : roles.onSurface,
      rail: WebsiteRgba.fromArgb(rail),
      railForeground: light(rail) ? WebsiteRgba.white : roles.onSurface,
    );
  }

  static int _argb(WebsiteRgba c) {
    int channel(double v) => (v * 255).round() & 0xFF;
    return channel(c.a) << 24 |
        channel(c.r) << 16 |
        channel(c.g) << 8 |
        channel(c.b);
  }

  final WebsiteRgba surface;

  /// White words on the open menu's surface, header included.
  final bool surfaceLight;
  final WebsiteRgba panelForeground;
  final WebsiteRgba rail;
  final WebsiteRgba railForeground;
}

/// One desktop header item with children: the wide panel or the compact list.
Component headerMenuItem(StorefrontShell shell, WebsiteNavigation item) {
  final children = _desktop(item.children);
  final wide =
      item.cssClass?.split(RegExp(r'\s+')).contains('megamenu') == true;
  return wide
      ? _MegaMenu(shell, item, children).build()
      : _dropdown(shell, item, children);
}

List<WebsiteNavigation> _desktop(Iterable<WebsiteNavigation> nodes) =>
    nodes.where((node) => node.isVisible && node.showOnDesktop).toList()
      ..sort((x, y) => x.orderIndex.compareTo(y.orderIndex));

bool _isDirect(WebsiteNavigation node) {
  final uri = Uri.tryParse(node.href?.trim() ?? '');
  return uri != null &&
      WebsiteCatalogQuery.tryParse(uri)?.categoryScope ==
          WebsiteCatalogCategoryScope.direct;
}

Component _trigger(WebsiteNavigation item, String controls, String classes) =>
    button(
      classes: classes,
      attributes: {
        'type': 'button',
        'aria-expanded': 'false',
        'aria-controls': controls,
      },
      [.text(item.label)],
    );

String _domId(String prefix, WebsiteNavigation item) =>
    '$prefix-${item.id.isEmpty ? item.label.hashCode.abs() : item.id}';

class _MegaMenu {
  _MegaMenu(this.shell, this.parent, this.roots);

  final StorefrontShell shell;
  final WebsiteNavigation parent;
  final List<WebsiteNavigation> roots;

  String? _href(WebsiteNavigation node) => shell.hrefFor(node);

  Component build() {
    final id = _domId('mega', parent);
    final structured = roots.any((root) => _desktop(root.children).isNotEmpty);
    // The branch the panel opens on, and returns to when the pointer rests
    // on the rail between tabs: the first that has children.
    final first = structured
        ? roots.firstWhere((root) => _desktop(root.children).isNotEmpty)
        : null;
    final all = _href(parent);
    return li(
      classes: 'has-mega',
      attributes: {'data-mega': ''},
      [
        _trigger(parent, id, 'mega-btn'),
        div(
          id: id,
          classes: 'mega',
          attributes: {'data-mega-panel': ''},
          [
            span(
              classes: 'mega-bridge',
              attributes: {'aria-hidden': 'true'},
              [],
            ),
            div(classes: 'mega-rail', [
              if (structured)
                div(classes: 'mega-tabs', [
                  for (final root in roots) _tab(root, active: root == first),
                ])
              else
                p(classes: 'mega-hint', [
                  .text('Seleccioná una opción para continuar'),
                ]),
              if (all != null)
                a(classes: 'mega-all mega-link', href: all, [
                  span([.text('VER TODO')]),
                  RawText(materialIcon(mdArrowForwardRounded, size: 14)),
                ]),
            ]),
            div(classes: 'mega-body', [
              if (structured)
                for (final root in roots) _branch(root, open: root == first)
              else
                _flat(),
            ]),
          ],
        ),
      ],
    );
  }

  /// `_MegaMenuSectionTab`: hovering or focusing it shows its branch, a click
  /// opens its page (or only shows it when it has none).
  Component _tab(WebsiteNavigation root, {required bool active}) {
    final href = _href(root);
    final classes = active ? 'mega-tab on' : 'mega-tab';
    final content = [
      span([.text(root.label.toUpperCase())]),
      Component.element(tag: 'i', attributes: {'aria-hidden': 'true'}),
    ];
    final data = {'data-branch': root.id};
    return href == null
        ? button(
            classes: classes,
            attributes: {'type': 'button', ...data},
            content,
          )
        : a(classes: classes, href: href, attributes: data, content);
  }

  Component _branch(WebsiteNavigation branch, {required bool open}) {
    final presentation = megaMenuPresentationOf(branch, shell.presentations);
    final children = _desktop(branch.children);
    return section(
      classes: 'mega-branch',
      attributes: {'data-branch': branch.id, if (!open) 'hidden': ''},
      [
        _overview(branch, presentation),
        if (children.isNotEmpty) ...[
          _level(branch, owner: branch, previous: null, open: true),
          for (final (owner, previous) in _drillLevels(branch))
            _level(branch, owner: owner, previous: previous, open: false),
        ],
      ],
    );
  }

  /// Every card that opens a level of its own, with the level it returns to.
  List<(WebsiteNavigation, WebsiteNavigation)> _drillLevels(
    WebsiteNavigation owner,
  ) => [
    for (final node in _desktop(owner.children))
      if (_desktop(node.children).isNotEmpty) ...[
        (node, owner),
        ..._drillLevels(node),
      ],
  ];

  /// `_buildBranchOverviewCard`: the section's photo behind a veil that
  /// thins to the right, «SECCIÓN», its name, a rule and «Explorar …».
  Component _overview(
    WebsiteNavigation branch,
    WebsiteCatalogPresentation? presentation,
  ) {
    final image = presentation?.megaMenuImageUrl.trim() ?? '';
    final overlay = (presentation?.megaMenuOverlay ?? 0.58).clamp(0.0, 0.85);
    final center = math.max(0.08, overlay * 0.34);
    final width =
        (presentation?.megaMenuOverviewWidth ??
                WebsiteCatalogPresentation.defaultMegaMenuOverviewWidth)
            .clamp(
              WebsiteCatalogPresentation.minMegaMenuOverviewWidth,
              WebsiteCatalogPresentation.maxMegaMenuOverviewWidth,
            )
            .toDouble();
    final align = switch (presentation?.megaMenuContentAlignment ??
        WebsiteMegaMenuContentAlignment.bottom) {
      WebsiteMegaMenuContentAlignment.top => 'flex-start',
      WebsiteMegaMenuContentAlignment.center => 'center',
      WebsiteMegaMenuContentAlignment.bottom => 'flex-end',
    };
    final href = _href(branch);
    return div(
      classes: image.isEmpty ? 'mega-ov' : 'mega-ov photo',
      attributes: {'style': 'width:${cssPx(width)}'},
      [
        if (image.isNotEmpty) ...[
          img(
            src: image,
            alt: 'Imagen de ${branch.label}',
            loading: MediaLoading.lazy,
            attributes: {'decoding': 'async'},
          ),
          span(
            classes: 'mega-veil',
            attributes: {
              'style':
                  'background:linear-gradient(90deg,rgb(0 0 0 / ${cssNum(overlay)}) 0%,'
                  'rgb(0 0 0 / ${cssNum(center)}) 48%,transparent 86%)',
            },
            [],
          ),
        ],
        div(
          classes: 'mega-ov-in',
          attributes: {'style': 'justify-content:$align'},
          [
            span(classes: 'mega-eyebrow', [.text('SECCIÓN')]),
            span(classes: 'mega-title', [.text(branch.label)]),
            span(classes: 'mega-rule', []),
            if (href != null)
              a(classes: 'mega-explore mega-link', href: href, [
                span([.text('Explorar ${branch.label}')]),
                RawText(materialIcon(mdArrowForwardRounded, size: 14)),
              ]),
          ],
        ),
      ],
    );
  }

  /// `_buildVisualCategoryBrowser`: the cards of one level; below the
  /// branch, with «Volver a …» and «VER TODO EN …» above them.
  Component _level(
    WebsiteNavigation branch, {
    required WebsiteNavigation owner,
    required WebsiteNavigation? previous,
    required bool open,
  }) {
    final href = previous == null ? null : _href(owner);
    return div(
      classes: 'mega-level',
      attributes: {'data-level': owner.id, if (!open) 'hidden': ''},
      [
        if (previous != null)
          div(classes: 'mega-level-head', [
            button(
              classes: 'mega-back',
              attributes: {'type': 'button', 'data-back': ''},
              [
                RawText(materialIcon(mdArrowBackRounded, size: 17)),
                span([.text('Volver a ${previous.label}')]),
              ],
            ),
            if (href != null)
              a(classes: 'mega-in-all mega-link', href: href, [
                span([.text('VER TODO EN ${owner.label.toUpperCase()}')]),
                RawText(materialIcon(mdArrowForwardRounded, size: 14)),
              ]),
          ]),
        div(classes: 'mega-grid', [
          for (final node in _desktop(owner.children)) _card(node),
        ]),
      ],
    );
  }

  /// `_MegaMenuMediaCard`: the artwork leads to the products, the caption
  /// under it says how many subcategories it opens (or that it shows only
  /// this category), and hovering the caption previews them.
  Component _card(WebsiteNavigation node) {
    final presentation = megaMenuPresentationOf(node, shell.presentations);
    final image = presentation?.megaMenuImageUrl.trim() ?? '';
    final dim = (presentation?.megaMenuCardOverlay ?? 0).clamp(0.0, 0.65);
    final kids = _desktop(node.children);
    final direct = _href(node) != null && _isDirect(node);
    final href = _href(node);
    final count = kids.length;
    final preview = kids.take(5).toList();
    final more = kids.length - preview.length;
    final art = [
      if (image.isNotEmpty)
        img(
          classes: 'mega-img',
          src: image,
          alt: '',
          loading: MediaLoading.lazy,
          attributes: {'decoding': 'async'},
        )
      else
        RawText(materialIcon(mdImageOutlined, size: 30, classes: 'mega-ph')),
      if (dim > 0)
        span(
          classes: 'mega-dim',
          attributes: {'style': 'background:rgb(0 0 0 / ${cssNum(dim)})'},
          [],
        ),
      span(classes: 'mega-shade', []),
      span(classes: 'mega-face mega-name', [
        b([.text(node.label)]),
        small([.text(direct ? 'Solo esta categoría' : 'Ver productos')]),
      ]),
      if (kids.isNotEmpty)
        span(classes: 'mega-face mega-peek', [
          for (final kid in preview) b([.text(kid.label)]),
          if (more > 0) small([.text('+$more más')]),
        ]),
    ];
    final label = direct
        ? 'Ver solo productos de ${node.label}'
        : 'Ver productos de ${node.label}';
    final caption = kids.isNotEmpty
        ? (count == 1 ? '1 SUBCATEGORÍA' : '$count SUBCATEGORÍAS')
        : 'SOLO ESTA CATEGORÍA';
    return div(classes: kids.isEmpty ? 'mega-card' : 'mega-card kids', [
      if (href != null)
        a(
          classes: 'mega-art',
          href: href,
          attributes: {'aria-label': label},
          art,
        )
      else
        button(
          classes: 'mega-art',
          attributes: {
            'type': 'button',
            'aria-label': label,
            if (kids.isNotEmpty) 'data-open': node.id,
          },
          art,
        ),
      if (kids.isNotEmpty)
        button(
          classes: 'mega-cap',
          attributes: {
            'type': 'button',
            'data-open': node.id,
            'aria-label': 'Ver las $count subcategorías de ${node.label}',
          },
          [
            span([.text(caption)]),
            RawText(materialIcon(mdChevronRightRounded, size: 16)),
          ],
        )
      else if (direct && href != null)
        a(
          classes: 'mega-cap',
          href: href,
          attributes: {'aria-label': label},
          [
            span([.text(caption)]),
            RawText(materialIcon(mdArrowForwardRounded, size: 16)),
          ],
        ),
    ]);
  }

  /// `_buildFlatRootGrid`: a branchless panel lists its items in three
  /// columns.
  Component _flat() => div(classes: 'mega-flat', [
    for (final node in roots)
      if (_href(node) case final href?)
        a(classes: 'mega-flat-item', href: href, [
          span([
            b([.text(node.label)]),
          ]),
          RawText(materialIcon(mdArrowOutwardRounded, size: 17)),
        ]),
  ]);
}

/// `NavigationDropdownButton`: a click opens the list of the branch, «VER
/// TODO …» first, each level indented 18 px.
Component _dropdown(
  StorefrontShell shell,
  WebsiteNavigation item,
  List<WebsiteNavigation> children,
) {
  final id = _domId('drop', item);
  final all = shell.hrefFor(item);
  Iterable<Component> rows(WebsiteNavigation node, int depth) sync* {
    final kids = _desktop(node.children);
    final href = shell.hrefFor(node);
    final content = [
      span([
        b([.text(node.label)]),
        if (href != null && _isDirect(node))
          small([.text('Solo esta categoría')]),
      ]),
      if (kids.isNotEmpty)
        RawText(materialIcon(mdKeyboardArrowDownRounded, size: 17)),
    ];
    final classes = [
      'drop-item',
      if (depth > 0) 'deep',
      if (kids.isNotEmpty || depth == 0) 'strong',
    ].join(' ');
    final style = {'style': 'padding-left:${16 + depth * 18}px'};
    yield href == null
        ? div(classes: '$classes off', attributes: style, content)
        : a(classes: classes, href: href, attributes: style, content);
    for (final kid in kids) {
      yield* rows(kid, depth + 1);
    }
    if (depth == 0 && kids.isNotEmpty) yield hr(classes: 'drop-rule');
  }

  return li(
    classes: 'has-drop',
    attributes: {'data-drop': ''},
    [
      _trigger(item, id, 'drop-btn'),
      div(
        id: id,
        classes: 'drop',
        attributes: {'role': 'menu', 'hidden': ''},
        [
          if (all != null) ...[
            a(classes: 'drop-item drop-all', href: all, [
              span([
                b([.text('VER TODO ${item.label.toUpperCase()}')]),
              ]),
              RawText(materialIcon(mdArrowOutwardRounded, size: 16)),
            ]),
            if (children.isNotEmpty) hr(classes: 'drop-top'),
          ],
          for (final child in children) ...rows(child, 0),
        ],
      ),
    ],
  );
}

/// The panel's and the list's styles, with the editor's menu colors. The
/// sizes are Flutter's at the store theme's density (−4 px on every button's
/// height and vertical padding); a text line is its size times the Material
/// 3 height of its style, rounded as SkParagraph rounds. Flutter gives a
/// line's extra room to the ascent and descent in proportion
/// (`TextLeadingDistribution.proportional`), CSS half and half: Barlow
/// (ascent 1, descent 0.2) sits (line − 1.2 × size) / 3 px lower in Flutter,
/// so those texts move down by that much.
String headerMenuCss(HeaderMenuColors colors) {
  final fg = colors.panelForeground;
  final railFg = colors.railForeground;
  String tint(WebsiteRgba color, double alpha) => color.withAlpha(alpha).css;
  return '''
.menu>ul>li.has-mega{position:static}
.mega-btn,.drop-btn{display:flex;align-items:center;height:31px;padding:6.4px 0 3.6px;border:0;border-radius:4px;background:transparent;color:rgb(0 0 0 / .87);font:600 14px/21px var(--body);letter-spacing:.1px;text-transform:uppercase;white-space:nowrap;cursor:pointer;transition:background-color .25s}
.mega-btn::after,.drop-btn::after{content:"";width:18px;height:18px;margin-left:4px;background:currentColor;-webkit-mask:var(--chevron) center/18px no-repeat;mask:var(--chevron) center/18px no-repeat;position:relative;top:-1.4px;transition:transform .25s}
.has-mega.open>.mega-btn,.mega-btn:focus-visible{background:color-mix(in srgb,var(--primary) 8%,transparent)}
.has-mega.open>.mega-btn::after{transform:rotate(-180deg)}
.mega-btn:focus-visible,.drop-btn:focus-visible{outline:0}
.top{transition:background-color .3s ease-in-out}
.top.mega-open{background-color:${colors.surface.css}}
.mega{position:absolute;top:100%;left:0;right:0;z-index:30;display:none;flex-direction:column;max-height:520px;background:${colors.surface.css};border-block:1px solid ${tint(fg, .14)};box-shadow:0 4px 5px rgb(0 0 0 / .1),0 1px 10px rgb(0 0 0 / .08);opacity:0;transform:translateY(-8px);transition:opacity .19s cubic-bezier(.325,.81,.45,.945),transform .19s cubic-bezier(.325,.81,.45,.945);color:${fg.css}}
.has-mega.open>.mega{display:flex}
.has-mega.open.in>.mega{opacity:1;transform:none;transition-timing-function:cubic-bezier(.215,.61,.355,1)}
html:not(.js) .has-mega:hover>.mega{display:flex;opacity:1;transform:none}
.mega-bridge{position:absolute;left:0;right:0;bottom:100%;height:13px}
.mega-rail{flex:none;display:flex;align-items:center;min-height:62px;padding:0 28px;background:${colors.rail.css};color:${railFg.css}}
.mega-tabs{flex:1;display:flex;flex-wrap:wrap;column-gap:30px;row-gap:2px;min-width:0}
.mega-tab{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;min-height:58px;padding:8px 0;border:0;background:none;color:inherit;font:600 12px/16px var(--body);letter-spacing:.7px;text-decoration:none;cursor:pointer}
.mega-tab span{position:relative;top:.53px;opacity:.67}
.mega-tab.on span{opacity:1;font-weight:800}
.mega-tab i{display:block;width:0;height:2px;background:currentColor;transition:width .13s ease-out}
.mega-tab.on i{width:30px}
.mega-tab:hover,.mega-tab:focus-visible{background:${tint(railFg, .06)};outline:0}
.mega-hint{flex:1;margin:0;position:relative;top:1.2px;font:500 12px/18px var(--body);color:${tint(railFg, .62)}}
.mega-link{display:inline-flex;align-items:center;gap:6px;min-height:26px;border-radius:999px;color:inherit;text-decoration:none;white-space:nowrap}
.mega-link:hover,.mega-link:focus-visible{background:${tint(fg, .06)};outline:0}
.mega-all{flex:none;height:62px;margin-left:28px;font:800 12px/16px var(--body);letter-spacing:.8px}
.mega-link>span{position:relative;top:.53px}
.mega-all:hover,.mega-all:focus-visible{background:${tint(railFg, .06)}}
.mega-body{position:relative;flex:1 1 auto;min-height:0;overflow-y:auto}
.mega-branch{position:relative;z-index:1;display:flex;height:440px;background:${colors.surface.css}}
.mega-branch.enter{animation:mega-in .15s ease-out}
.mega-ghost{position:absolute;top:0;left:0;right:0;z-index:0;pointer-events:none;animation:mega-out .15s ease-out forwards}
@keyframes mega-in{from{opacity:0}}@keyframes mega-out{to{opacity:0}}
.mega-ov{position:relative;flex:none;overflow:hidden;background:${colors.surface.css};color:${fg.css}}
.mega-ov.photo{color:#fff}
.mega-ov img{position:absolute;inset:0;width:100%;height:100%;max-width:none;object-fit:cover}
.mega-veil{position:absolute;inset:0}
.mega-ov-in{position:absolute;inset:18px;display:flex;flex-direction:column;align-items:flex-start}
.mega-eyebrow{position:relative;top:1.07px;font:800 14px/20px var(--body);letter-spacing:1.35px;opacity:.72}
.mega-title{max-width:100%;margin-top:8px;font:400 30px/39px var(--head);-webkit-text-stroke:.032em currentColor;letter-spacing:-.6px;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;transform-origin:left center}
.mega-rule{width:44px;height:3px;margin-top:13px;background:currentColor;opacity:.88;transform-origin:left center}
.mega-explore>span{top:.93px}
.mega-explore{margin-top:13px;font:600 16px/22px var(--body);letter-spacing:.25px;color:color-mix(in srgb,currentColor 86%,transparent)}
.mega-explore:hover,.mega-explore:focus-visible{color:inherit;background:color-mix(in srgb,currentColor 6%,transparent)}
.play .mega-eyebrow{animation:mega-reveal-8 .55s cubic-bezier(.645,.045,.355,1) both}
.play .mega-title{animation:mega-reveal-title .7s cubic-bezier(.645,.045,.355,1) .15s both}
.play .mega-rule{animation:mega-reveal-rule .625s cubic-bezier(.645,.045,.355,1) .35s both}
.play .mega-explore{animation:mega-reveal-6 .725s cubic-bezier(.645,.045,.355,1) .525s both}
@keyframes mega-reveal-8{from{opacity:0;transform:translateX(-8%)}}
@keyframes mega-reveal-6{from{opacity:0;transform:translateX(-6%)}}
@keyframes mega-reveal-title{from{opacity:0;transform:translateX(-10%) scale(.965)}}
@keyframes mega-reveal-rule{from{transform:scaleX(0)}}
@media (prefers-reduced-motion:reduce){.play .mega-eyebrow,.play .mega-title,.play .mega-rule,.play .mega-explore{animation:none}}
.mega-level{flex:1;min-width:0;display:flex;flex-direction:column;padding:20px 28px 22px 30px;container:mega-level/inline-size}
.mega-level-head{flex:none;display:flex;align-items:center;justify-content:space-between;margin-bottom:14px}
.mega-back{display:inline-flex;align-items:center;gap:8px;min-height:32px;padding:0 9px;border:1px solid ${tint(fg, .22)};border-radius:999px;background:none;color:${fg.css};font:700 12px/14px "vb-roboto",var(--body);-webkit-text-stroke:.0405em currentColor;letter-spacing:.1px;cursor:pointer}
.mega-back:hover,.mega-back:focus-visible{background:${tint(fg, .08)};outline:0}
.mega-in-all>span{top:.6px}
.mega-in-all{font:800 11px/15px var(--body);letter-spacing:.65px;color:${tint(fg, .66)}}
.mega-in-all:hover,.mega-in-all:focus-visible{color:${fg.css}}
.mega-grid{flex:1;min-height:0;overflow-y:auto;display:grid;grid-template-columns:minmax(0,1fr);grid-auto-rows:184px;gap:16px 18px;align-content:start}
${_gridColumns()}
.mega-card{display:flex;flex-direction:column;min-width:0}
.mega-art{position:relative;flex:1;min-height:0;display:block;padding:0;border:0;border-radius:3px;overflow:hidden;background:color-mix(in srgb,${fg.css} 8%,${colors.surface.css});color:#fff;text-decoration:none;cursor:pointer}
.mega-art:focus-visible{outline:2px solid ${fg.css};outline-offset:2px}
.mega-img{position:absolute;inset:0;width:100%;height:100%;max-width:none;object-fit:cover;transition:transform .22s cubic-bezier(.215,.61,.355,1)}
.mega-ph{position:absolute;inset:0;margin:auto;color:${tint(fg, .38)}}
.mega-dim,.mega-shade{position:absolute;inset:0}
.mega-shade{transition:background-color .19s cubic-bezier(.215,.61,.355,1)}
.mega-face{position:absolute;left:14px;right:14px;top:50%;display:flex;flex-direction:column;align-items:center;text-align:center;transform:translateY(-50%)}
.mega-name b{max-width:100%;font:400 20px/25px var(--head);-webkit-text-stroke:.032em currentColor;letter-spacing:-.2px;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical}
.mega-name small{position:relative;top:.93px;margin-top:4px;font:600 11px/16px var(--body);letter-spacing:.2px;color:rgb(255 255 255 / .82)}
.mega-peek b{position:relative;top:.53px;max-width:100%;padding:1.5px 0;font:700 12px/16px var(--body);letter-spacing:.5px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.mega-peek small{position:relative;top:1px;padding-top:3px;font:600 10px/15px var(--body);letter-spacing:.5px;color:rgb(255 255 255 / .68)}
.mega-name{transition:opacity .17s cubic-bezier(.215,.61,.355,1),transform .17s cubic-bezier(.215,.61,.355,1)}
.mega-peek{opacity:0;transform:translateY(-50%) scale(.985);transition:opacity .14s cubic-bezier(.325,.81,.45,.945),transform .14s cubic-bezier(.325,.81,.45,.945)}
.mega-card.kids:has(.mega-cap:hover,.mega-cap:focus-visible) .mega-img{transform:scale(1.018)}
.mega-card.kids:has(.mega-cap:hover,.mega-cap:focus-visible) .mega-shade{background:rgb(0 0 0 / .68)}
.mega-card.kids:has(.mega-cap:hover,.mega-cap:focus-visible) .mega-name{opacity:0;transform:translateY(-50%) scale(.985);transition-duration:.14s;transition-timing-function:cubic-bezier(.325,.81,.45,.945)}
.mega-card.kids:has(.mega-cap:hover,.mega-cap:focus-visible) .mega-peek{opacity:1;transform:translateY(-50%);transition-duration:.17s;transition-timing-function:cubic-bezier(.215,.61,.355,1)}
.mega-cap span{position:relative;top:1px}
.mega-cap{flex:none;align-self:flex-end;display:inline-flex;align-items:center;gap:5px;margin-top:5px;padding:2px 0;border:0;border-radius:3px;background:none;color:#3b82f6;font:800 10px/15px var(--body);letter-spacing:.45px;text-decoration:none;cursor:pointer}
.mega-cap:hover{background:rgb(0 0 0 / .04)}.mega-cap:focus-visible{outline:2px solid #3b82f6;outline-offset:1px}
.mega-flat{display:flex;flex-wrap:wrap;gap:10px 18px;padding:24px 28px 28px}
.mega-flat-item{display:flex;align-items:center;gap:8px;width:calc((100% - 36px) / 3);min-height:50px;padding:7px 10px;border-bottom:1px solid ${tint(fg, .14)};color:${fg.css};text-decoration:none}
.mega-flat-item span{flex:1;min-width:0}.mega-flat-item b{position:relative;top:1.4px;display:block;font:700 14px/21px var(--body);letter-spacing:.05px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.mega-flat-item svg{color:${tint(fg, .58)}}
.mega-flat-item:hover,.mega-flat-item:focus-visible{background:${tint(fg, .065)};outline:0}
.has-drop{position:relative}
.drop-btn{height:30px;letter-spacing:.25px}
.has-drop.open>.drop-btn,.drop-btn:hover,.drop-btn:focus-visible{background:color-mix(in srgb,currentColor 8%,transparent)}
.has-drop.open>.drop-btn::after{transform:rotate(-180deg);transition-duration:.16s}
.drop{position:absolute;top:calc(100% - 13px);left:0;z-index:30;max-width:390px;max-height:560px;overflow-y:auto;padding:8px 0;border:1px solid ${tint(fg, .16)};border-radius:2px;background:${colors.surface.css};color:${fg.css};box-shadow:0 2px 4px rgb(0 0 0 / .14),0 4px 8px rgb(0 0 0 / .1)}
.drop-item{display:flex;align-items:center;gap:8px;min-width:280px;min-height:44px;padding:6px 14px 6px 16px;color:${fg.css};text-decoration:none}
.drop-item span{flex:1;display:flex;flex-direction:column}
.drop-item b{position:relative;top:1.4px;font:500 14px/21px var(--body);color:${tint(fg, .74)}}
.drop-item.strong b{font-weight:700}.drop-item:not(.deep) b{color:${tint(fg, .96)}}
.drop-item small{position:relative;top:1px;font:600 10px/15px var(--body);color:${tint(fg, .52)}}
.drop-item svg{color:${tint(fg, .55)}}
.drop-all b{font:800 12px/16px var(--body)!important;letter-spacing:.8px;color:${fg.css}!important}.drop-all svg{color:${tint(fg, .7)}}
a.drop-item:hover,a.drop-item:focus-visible{background:${tint(fg, .08)};outline:0}
.drop hr{margin:0;border:0}.drop-top{height:17px;background:linear-gradient(${tint(fg, .14)},${tint(fg, .14)}) center/100% 1px no-repeat}
.drop-rule{height:13px;background:linear-gradient(${tint(fg, .1)},${tint(fg, .1)}) center/100% 1px no-repeat}
''';
}

/// `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 286,
/// crossAxisSpacing: 18)`: as many columns as `ceil(width / 304)`, all equal.
String _gridColumns() => [
  for (var n = 2; n <= 9; n++)
    '@container mega-level (min-width:${(n - 1) * 304}.01px)'
        '{.mega-grid{grid-template-columns:repeat($n,minmax(0,1fr))}}',
].join('\n');

/// The header menus' behavior, Flutter's timings: the wide panel opens 110 ms
/// after the pointer rests on its button and closes 180 ms after it leaves
/// both (`_scheduleOpen`/`_scheduleClose`), fading in 190 ms; a click toggles
/// it, Escape and a click below the header close it at once. A tab shows its
/// branch while hovered or focused and, 220 ms after the pointer rests on the
/// rail between tabs, the first branch again. A card's caption opens its
/// subcategories; every switch cross-fades in 150 ms (`AnimatedSwitcher`)
/// and replays the section's reveal. The compact list opens on click.
const headerMenuScript = r'''
(function () {
  var header = document.querySelector('header.top');
  if (!header) return;
  var slice = Array.prototype.slice;

  slice.call(header.querySelectorAll('[data-mega]')).forEach(function (item) {
    var btn = item.querySelector('.mega-btn');
    var panel = item.querySelector('.mega');
    var body = panel.querySelector('.mega-body');
    var rail = panel.querySelector('.mega-rail');
    var tabs = slice.call(panel.querySelectorAll('.mega-tab'));
    var firstTab = panel.querySelector('.mega-tab.on');
    var fallback = firstTab ? firstTab.dataset.branch : null;
    var open = false, closing = false, focused = false, suppress = false;
    var overButton = false, overPanel = false, focusIn = false;
    var openTimer = 0, closeTimer = 0, endTimer = 0, railTimer = 0;
    var hovered = null, path = [], insideRail = false, overTab = null, shown = '';

    function busy() { return overButton || overPanel || focusIn; }
    function section(id) { return panel.querySelector('.mega-branch[data-branch="' + id + '"]'); }
    function branchId() { return hovered && section(hovered) ? hovered : fallback; }

    function replay(el, name) { el.classList.remove(name); void el.offsetWidth; el.classList.add(name); }

    // The one place that draws the active branch and level, as the panel's
    // `KeyedSubtree('${active.id}|$drilldownKey')`.
    function render(animate) {
      var id = branchId();
      if (!id) return;
      var level = path.length ? path[path.length - 1] : id;
      var key = id + '|' + path.join('/');
      if (key === shown) return;
      var before = shown && section(shown.split('|')[0]);
      if (animate && before) {
        var ghost = before.cloneNode(true);
        ghost.removeAttribute('data-branch');
        ghost.classList.remove('enter');
        ghost.classList.add('mega-ghost');
        slice.call(ghost.querySelectorAll('.play')).forEach(function (el) { el.classList.remove('play'); });
        ghost.setAttribute('aria-hidden', 'true');
        ghost.inert = true;
        ghost.style.height = before.offsetHeight + 'px';
        body.appendChild(ghost);
        var drop = function () { if (ghost.parentNode) ghost.parentNode.removeChild(ghost); };
        ghost.addEventListener('animationend', drop);
        setTimeout(drop, 400);
      }
      shown = key;
      slice.call(panel.querySelectorAll('.mega-branch')).forEach(function (el) {
        el.hidden = el.dataset.branch !== id;
      });
      var now = section(id);
      slice.call(now.querySelectorAll('.mega-level')).forEach(function (el) {
        el.hidden = el.dataset.level !== level;
      });
      tabs.forEach(function (tab) { tab.classList.toggle('on', tab.dataset.branch === id); });
      var overview = now.querySelector('.mega-ov');
      if (overview) replay(overview, 'play');
      if (animate) replay(now, 'enter');
    }

    function select(id) {
      if (hovered === id && !path.length) return;
      hovered = id; path = [];
      render(true);
    }

    function collapseIfBlank() {
      clearTimeout(railTimer);
      railTimer = setTimeout(function () {
        if (!insideRail || overTab !== null || hovered === null) return;
        hovered = null; path = [];
        render(true);
      }, 220);
    }

    function fit() {
      var top = header.getBoundingClientRect().bottom;
      panel.style.maxHeight = Math.max(180, Math.min(520, innerHeight - top - 12)) + 'px';
    }

    function show() {
      if (open) return;
      clearTimeout(openTimer); clearTimeout(closeTimer); clearTimeout(endTimer);
      open = true; closing = false;
      hovered = null; path = []; shown = '';
      fit();
      item.classList.add('open');
      btn.setAttribute('aria-expanded', 'true');
      header.classList.add('mega-open');
      render(false);
      void panel.offsetWidth;
      item.classList.add('in');
    }

    function finish() {
      open = false; closing = false;
      item.classList.remove('open', 'in');
      btn.setAttribute('aria-expanded', 'false');
      header.classList.remove('mega-open');
    }

    function forceClose() {
      clearTimeout(openTimer); clearTimeout(closeTimer); clearTimeout(endTimer);
      suppress = true;
      if (open) finish();
    }

    function reopen() {
      closing = false;
      clearTimeout(endTimer);
      header.classList.add('mega-open');
      item.classList.add('in');
    }

    function requestClose() {
      if (!open || busy()) return;
      closing = true;
      header.classList.remove('mega-open');
      item.classList.remove('in');
      endTimer = setTimeout(function () {
        if (busy()) reopen(); else finish();
      }, 190);
    }

    function scheduleOpen() {
      if (open) return;
      clearTimeout(closeTimer); clearTimeout(openTimer);
      openTimer = setTimeout(function () { if (overButton || focused) show(); }, 110);
    }

    function scheduleClose() {
      clearTimeout(openTimer); clearTimeout(closeTimer);
      closeTimer = setTimeout(requestClose, 180);
    }

    btn.addEventListener('mouseenter', function () { overButton = true; scheduleOpen(); });
    btn.addEventListener('mouseleave', function () { overButton = false; scheduleClose(); });
    btn.addEventListener('click', function () {
      if (open) { overButton = overPanel = focusIn = false; forceClose(); } else show();
    });
    btn.addEventListener('focus', function () {
      if (!btn.matches(':focus-visible')) return;
      focused = true;
      if (!suppress) scheduleOpen();
    });
    btn.addEventListener('blur', function () {
      focused = false;
      if (!overButton) { suppress = false; scheduleClose(); }
    });
    btn.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowDown') { event.preventDefault(); show(); }
    });

    panel.addEventListener('mouseenter', function () {
      overPanel = true;
      clearTimeout(closeTimer);
      if (closing) reopen();
    });
    panel.addEventListener('mouseleave', function () { overPanel = false; scheduleClose(); });
    panel.addEventListener('focusin', function () { focusIn = true; clearTimeout(closeTimer); });
    panel.addEventListener('focusout', function (event) {
      if (panel.contains(event.relatedTarget)) return;
      focusIn = false;
      scheduleClose();
    });

    rail.addEventListener('mouseenter', function () { insideRail = true; collapseIfBlank(); });
    rail.addEventListener('mouseleave', function () { insideRail = false; clearTimeout(railTimer); });
    tabs.forEach(function (tab) {
      var id = tab.dataset.branch;
      tab.addEventListener('mouseenter', function () { clearTimeout(railTimer); overTab = id; select(id); });
      tab.addEventListener('mouseleave', function () { if (overTab === id) overTab = null; collapseIfBlank(); });
      tab.addEventListener('focus', function () { select(id); });
      if (tab.tagName === 'BUTTON') tab.addEventListener('click', function () { select(id); });
    });

    panel.addEventListener('click', function (event) {
      var target = event.target.closest('[data-open],[data-back],a');
      if (!target || !panel.contains(target)) return;
      if (target.hasAttribute('data-back')) {
        path.pop();
        render(true);
      } else if (target.hasAttribute('data-open')) {
        var id = target.dataset.open;
        if (section(branchId()).querySelector('.mega-level[data-level="' + id + '"]')) {
          path.push(id);
          render(true);
        }
      } else {
        overButton = overPanel = focusIn = false;
        forceClose();
      }
    });

    item.addEventListener('keydown', function (event) {
      if (event.key !== 'Escape' || !open) return;
      overButton = overPanel = focusIn = false;
      forceClose();
      btn.focus();
    });

    document.addEventListener('pointerdown', function (event) {
      if (open && !header.contains(event.target)) {
        overButton = overPanel = focusIn = false;
        forceClose();
      }
    });
    addEventListener('resize', function () { if (open) fit(); });
    addEventListener('pageshow', function () { if (open) forceClose(); });
  });

  slice.call(header.querySelectorAll('[data-drop]')).forEach(function (item) {
    var btn = item.querySelector('.drop-btn');
    var list = item.querySelector('.drop');
    function toggle(open) {
      item.classList.toggle('open', open);
      list.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
    }
    btn.addEventListener('click', function () { toggle(list.hidden); });
    item.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && !list.hidden) { toggle(false); btn.focus(); }
    });
    document.addEventListener('pointerdown', function (event) {
      if (!list.hidden && !item.contains(event.target)) toggle(false);
    });
  });
})();
''';
