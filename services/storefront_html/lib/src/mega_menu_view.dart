import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_public_core/modules/website/models/website_menu_icons.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_models.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/header_menu_help.dart';
import 'package:vinabike_public_core/public_store/services/mega_menu_presentation.dart';
import 'package:vinabike_public_core/public_store/theme/header_menu_palette.dart';

import 'material_icons.dart';
import 'storefront_shell.dart';

/// The desktop header's menu with children, over the desktop projection
/// (`StorefrontShell.menuFor`): an item whose «Clase CSS» has `megamenu`
/// opens the wide panel, any other the compact list. Both triggers are
/// buttons; the item's own page is «Ver todo …» inside. Every link of the
/// panel is in the HTML from the start, so a crawler follows them without the
/// script.
///
/// The wide panel (2026-10-25, the owner's choice among two proposals): a
/// column with the first level as sections, each with its icon; the open
/// section's subcategories as names with their own subcategories in small
/// links under them; and at the right the section's photo («Catálogo web»)
/// over the help card. `lib/public_store/widgets/mega_menu.dart` draws the
/// same panel on the editor's Flutter canvas.
///
/// The phone and tablet never get here: below 1.080 px the header shows the
/// sheet (`PublicStoreHeaderGeometry`).
HeaderMenuPalette headerMenuPalette(
  StorefrontShell shell,
  WebsiteThemeRoles roles,
) => HeaderMenuPalette.resolve(roles, (key) => shell.setting(key));

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

/// How many small links a subcategory shows under its name before «Ver
/// más»: the rest are on its page.
const _subLinks = 8;

class _MegaMenu {
  _MegaMenu(this.shell, this.parent, this.sections);

  final StorefrontShell shell;
  final WebsiteNavigation parent;

  /// The first level: the column's sections.
  final List<WebsiteNavigation> sections;

  String? _href(WebsiteNavigation node) => shell.hrefFor(node);

  late final String _id = _domId('mega', parent);
  String _key(WebsiteNavigation node) =>
      node.id.isEmpty ? '${node.label.hashCode.abs()}' : node.id;

  Component build() {
    // A panel whose items have no children of their own has no sections:
    // its items are the names, under the menu's title.
    final structured = sections.any(
      (branch) => _desktop(branch.children).isNotEmpty,
    );
    final photos = structured
        ? [
            for (final branch in sections)
              if (_photo(branch) case final url?) (branch, url),
          ]
        : const <(WebsiteNavigation, String)>[];
    // Every row keeps the icon's place when any section has one.
    final icons = sections.any(
      (branch) => WebsiteMenuIcons.of(branch.icon) != null,
    );
    final help = HeaderMenuHelp.resolve(
      (key) => shell.setting(key),
      whatsappDigits: shell.whatsappDigits,
      storeName: shell.storeName,
    );
    final all = _href(parent);
    return li(
      classes: 'has-mega',
      attributes: {'data-mega': ''},
      [
        _trigger(parent, _id, 'mega-btn'),
        div(
          id: _id,
          classes: 'mega',
          attributes: {'data-mega-panel': ''},
          [
            span(
              classes: 'mega-bridge',
              attributes: {'aria-hidden': 'true'},
              [],
            ),
            if (structured)
              div(classes: 'mega-col', [
                div(
                  classes: 'mega-rail',
                  attributes: {
                    'role': 'tablist',
                    'aria-orientation': 'vertical',
                    'aria-label': parent.label,
                  },
                  [
                    for (final (index, branch) in sections.indexed)
                      _tab(branch, active: index == 0, iconSlot: icons),
                  ],
                ),
                if (all != null) _all(all),
              ]),
            div(classes: 'mega-main', [
              if (structured)
                for (final (index, branch) in sections.indexed)
                  _section(branch, open: index == 0)
              else
                _flat(all),
            ]),
            if (photos.isNotEmpty || help.show)
              Component.element(
                tag: 'aside',
                classes: 'mega-aside',
                children: [
                  for (final (branch, url) in photos)
                    img(
                      classes: 'mega-photo',
                      src: url,
                      alt: '',
                      loading: MediaLoading.lazy,
                      attributes: {
                        'decoding': 'async',
                        'data-branch': _key(branch),
                        if (branch != sections.first) 'hidden': '',
                      },
                    ),
                  if (help.show) _help(help),
                ],
              ),
          ],
        ),
      ],
    );
  }

  String? _photo(WebsiteNavigation branch) {
    final url =
        megaMenuPresentationOf(
          branch,
          shell.presentations,
        )?.megaMenuImageUrl.trim() ??
        '';
    return url.isEmpty ? null : url;
  }

  /// A row of the column: hovering, focusing or clicking it opens its
  /// section; its page is «Ver todo …» in the section.
  Component _tab(
    WebsiteNavigation branch, {
    required bool active,
    required bool iconSlot,
  }) {
    final key = _key(branch);
    final icon = WebsiteMenuIcons.of(branch.icon);
    return button(
      classes: active ? 'mega-sec on' : 'mega-sec',
      id: '$_id-t-$key',
      attributes: {
        'type': 'button',
        'role': 'tab',
        'aria-selected': '$active',
        'aria-controls': '$_id-p-$key',
        'tabindex': active ? '0' : '-1',
        'data-branch': key,
      },
      [
        if (iconSlot)
          span(classes: 'mega-ic', [if (icon != null) RawText(icon.svg())]),
        span(classes: 'mega-sec-l', [.text(branch.label)]),
        RawText(
          materialIcon(mdChevronRightRounded, size: 18, classes: 'mega-chev'),
        ),
      ],
    );
  }

  Component _all(String href) => a(classes: 'mega-all', href: href, [
    span([.text('Ver todo ${parent.label}')]),
    RawText(materialIcon(mdArrowForwardRounded, size: 16)),
  ]);

  /// The open section: its name and page, then its subcategories.
  Component _section(WebsiteNavigation branch, {required bool open}) {
    final key = _key(branch);
    final href = _href(branch);
    final groups = _desktop(branch.children);
    return _panel(
      key: key,
      open: open,
      label: branch.label,
      href: href,
      body: groups.isEmpty
          ? null
          : ul(classes: 'mega-grid', [
              for (final group in groups) _group(group),
            ]),
    );
  }

  Component _panel({
    required String key,
    required bool open,
    required String label,
    required String? href,
    required Component? body,
    bool tab = true,
  }) => section(
    classes: 'mega-branch',
    id: tab ? '$_id-p-$key' : null,
    attributes: {
      'data-branch': key,
      if (tab) 'role': 'tabpanel',
      if (tab) 'aria-labelledby': '$_id-t-$key',
      if (!open) 'hidden': '',
    },
    [
      div(classes: 'mega-head', [
        p(classes: 'mega-title', [.text(label)]),
        if (href != null)
          a(
            classes: 'mega-more',
            href: href,
            // The section as the editor names it, for the header's search
            // box (`menuCategories` in `search_overlay_view.dart`).
            attributes: {'data-label': label},
            [
              span([.text('Ver todo $label')]),
              RawText(materialIcon(mdArrowForwardRounded, size: 16)),
            ],
          ),
      ]),
      ?body,
    ],
  );

  /// A subcategory: its name, and its own subcategories under it.
  Component _group(WebsiteNavigation group) {
    final href = _href(group);
    final subs = [
      for (final sub in _desktop(group.children))
        if (_href(sub) case final subHref?) (sub, subHref),
    ];
    final shown = subs.take(_subLinks).toList();
    final more = subs.length - shown.length;
    return li(classes: 'mega-group', [
      if (href != null)
        a(classes: 'mega-name', href: href, [.text(group.label)])
      else
        span(classes: 'mega-name', [.text(group.label)]),
      if (shown.isNotEmpty)
        ul(classes: 'mega-subs', [
          for (final (sub, subHref) in shown)
            li([
              a(classes: 'mega-sub', href: subHref, [.text(sub.label)]),
            ]),
          if (more > 0 && href != null)
            li([
              a(classes: 'mega-sub mega-sub-more', href: href, [
                .text('Ver $more más'),
              ]),
            ]),
        ]),
    ]);
  }

  /// A panel without sections: the menu's own name over its items.
  Component _flat(String? all) => _panel(
    key: _key(parent),
    open: true,
    label: parent.label,
    href: all,
    tab: false,
    body: ul(classes: 'mega-grid', [
      for (final node in sections)
        if (_href(node) case final href?)
          li(classes: 'mega-group', [
            a(classes: 'mega-name', href: href, [.text(node.label)]),
          ]),
    ]),
  );

  Component _help(HeaderMenuHelp help) => div(classes: 'mega-help', [
    p(classes: 'mega-help-t', [
      RawText(materialIcon(mdChatBubbleOutline, size: 20)),
      span([.text(help.title)]),
    ]),
    p([.text(help.text)]),
    a(
      href: help.href,
      attributes: {
        if (help.external) 'rel': 'noopener',
        if (help.external) 'target': '_blank',
      },
      [
        span([.text(help.action)]),
        RawText(materialIcon(mdArrowForwardRounded, size: 16)),
      ],
    ),
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

/// The panel's and the list's styles, with the menu's colors
/// ([HeaderMenuPalette]). The panel dims the page under it with a shadow the
/// header does not get (`clip-path`); a section switches with a 150 ms fade.
/// Every section is laid out in the same cell, so the panel keeps the height
/// of its tallest and does not jump between them.
String headerMenuCss(HeaderMenuPalette c) {
  final on = c.onSurface;
  String tint(WebsiteRgba color, double alpha) => color.withAlpha(alpha).css;
  return '''
.menu>ul>li.has-mega{position:static}
.mega-btn,.drop-btn{display:flex;align-items:center;gap:2px;height:31px;padding:2px 0 0;border:0;border-bottom:2px solid transparent;border-radius:0;background:transparent;color:var(--ink);font:500 14px/21px var(--body);letter-spacing:.06em;text-transform:uppercase;white-space:nowrap;cursor:pointer}
.mega-btn::after,.drop-btn::after{content:"";width:16px;height:16px;background:currentColor;-webkit-mask:var(--chevron) center/16px no-repeat;mask:var(--chevron) center/16px no-repeat;transition:transform .2s}
.mega-btn:hover,.drop-btn:hover{border-bottom-color:color-mix(in srgb,currentColor 35%,transparent)}
.has-mega.open>.mega-btn,.has-drop.open>.drop-btn{border-bottom-color:currentColor}
.has-mega.open>.mega-btn::after,.has-drop.open>.drop-btn::after{transform:rotate(-180deg)}
.mega-btn:focus-visible,.drop-btn:focus-visible{outline:2px solid currentColor;outline-offset:4px;border-radius:2px}
.top{transition:background-color .3s ease-in-out}
.top.mega-open{background-color:${c.surface.css}}
.mega{position:absolute;top:100%;left:0;right:0;z-index:30;display:none;max-height:600px;background:${c.surface.css};color:${on.css};border-top:1px solid ${c.divider.css};box-shadow:0 30px 60px -24px rgb(15 23 42 / .32),0 0 0 100vmax rgb(11 14 19 / .32);clip-path:inset(0 -100vmax -100vmax);opacity:0;transform:translateY(-8px);transition:opacity .19s cubic-bezier(.325,.81,.45,.945),transform .19s cubic-bezier(.325,.81,.45,.945)}
.has-mega.open>.mega{display:flex}
.has-mega.open.in>.mega{opacity:1;transform:none;transition-timing-function:cubic-bezier(.215,.61,.355,1)}
html:not(.js) .has-mega:hover>.mega{display:flex;opacity:1;transform:none}
.mega-bridge{position:absolute;left:0;right:0;bottom:100%;height:13px}
.mega-col{flex:0 1 300px;min-width:240px;display:flex;flex-direction:column;padding:20px 14px 24px 26px;overflow-y:auto;background:${c.rail.css};border-right:1px solid ${c.divider.css};color:${c.onRail.css}}
.mega-rail{display:flex;flex-direction:column;gap:2px}
.mega-sec{display:flex;align-items:center;gap:12px;width:100%;min-height:44px;padding:0 12px;border:0;border-radius:8px;background:none;color:inherit;font:500 15px/1.2 var(--body);text-align:left;cursor:pointer;transition:background-color .12s}
.mega-sec:hover{background:${c.railHover.css}}
.mega-sec.on{background:${c.railActive.css};color:${c.onRailActive.css}}
.mega-ic{display:grid;place-items:center;flex:none;width:22px;height:22px;color:${c.ink.css}}
.mega-sec.on .mega-ic{color:inherit}
.mega-sec-l{flex:1;min-width:0}
.mega-chev{flex:none;color:${tint(c.onRail, .42)}}
.mega-sec.on .mega-chev{color:inherit}
.mega-all{display:flex;align-items:center;gap:8px;min-height:44px;margin-top:10px;padding:0 12px;border-top:1px solid ${c.divider.css};color:${c.ink.css};font:600 15px/1.2 var(--body);text-decoration:none}
.mega-main{flex:999 1 560px;min-width:0;display:grid;padding:28px 40px 32px;overflow-y:auto}
.mega-main>.mega-branch{grid-area:1/1;min-width:0}
.mega-main>.mega-branch[hidden]{display:block!important;visibility:hidden}
.mega-branch.enter,.mega-photo.enter{animation:mega-in .15s ease-out}
@keyframes mega-in{from{opacity:0}}
.mega-head{display:flex;flex-wrap:wrap;align-items:baseline;justify-content:space-between;gap:8px 24px;margin-bottom:20px}
.mega-title{margin:0;font:600 26px/1.15 var(--head);color:${on.css}}
.mega-more{display:inline-flex;align-items:center;gap:6px;color:${c.ink.css};font:600 15px/20px var(--body);text-decoration:none}
.mega-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:18px 32px;margin:0;padding:0;list-style:none;align-content:start}
.mega-name{color:${on.css};font:600 15px/1.35 var(--body);text-decoration:none}
.mega-subs{display:flex;flex-wrap:wrap;gap:0 12px;margin:3px 0 0;padding:0;list-style:none}
.mega-sub{color:${c.muted.css};font:400 14px/1.55 var(--body);text-decoration:none}
.mega-sub-more{color:${c.ink.css}}
:is(a.mega-name,.mega-sub,.mega-more,.mega-all,.mega-help a):hover{color:${c.ink.css};text-decoration:underline;text-underline-offset:3px}
:is(.mega-sec,a.mega-name,.mega-sub,.mega-more,.mega-all,.mega-help a):focus-visible{outline:2px solid ${c.ink.css};outline-offset:2px}
.mega-aside{flex:0 1 280px;min-width:220px;display:flex;flex-direction:column;gap:14px;padding:28px 40px 32px 0;overflow-y:auto}
.mega-photo{display:block;width:100%;max-width:100%;aspect-ratio:4/3;object-fit:cover;border-radius:6px}
.mega-help{display:flex;flex-direction:column;gap:6px;padding:18px;border-radius:8px;background:${c.helpFill.css}}
.mega-help p{margin:0;font:400 14px/1.5 var(--body);color:${c.muted.css}}
.mega-help .mega-help-t{display:flex;align-items:center;gap:10px;font:600 15px/1.3 var(--body);color:${on.css}}
.mega-help-t svg{flex:none;color:${c.ink.css}}
.mega-help a{display:inline-flex;align-items:center;gap:6px;margin-top:4px;color:${c.ink.css};font:600 14px/20px var(--body);text-decoration:none}
@media (max-width:1279px){.mega-main{padding-inline:28px}.mega-aside{flex-basis:240px;padding-right:28px}}
@media (prefers-reduced-motion:reduce){.mega,.mega-branch.enter,.mega-photo.enter{animation:none;transition:none}}
.has-drop{position:relative}
.drop{position:absolute;top:calc(100% - 13px);left:0;z-index:30;max-width:390px;max-height:560px;overflow-y:auto;padding:8px 0;border:1px solid ${tint(on, .16)};border-radius:8px;background:${c.surface.css};color:${on.css};box-shadow:0 18px 40px -18px rgb(15 23 42 / .35)}
.drop-item{display:flex;align-items:center;gap:8px;min-width:280px;min-height:44px;padding:6px 14px 6px 16px;color:${on.css};text-decoration:none}
.drop-item span{flex:1;display:flex;flex-direction:column}
.drop-item b{position:relative;top:1.4px;font:500 14px/21px var(--body);color:${tint(on, .74)}}
.drop-item.strong b{font-weight:700}.drop-item:not(.deep) b{color:${tint(on, .96)}}
.drop-item small{position:relative;top:1px;font:600 10px/15px var(--body);color:${tint(on, .52)}}
.drop-item svg{color:${tint(on, .55)}}
.drop-all b{font:800 12px/16px var(--body)!important;letter-spacing:.8px;color:${on.css}!important}.drop-all svg{color:${tint(on, .7)}}
a.drop-item:hover,a.drop-item:focus-visible{background:${tint(on, .08)};outline:0}
.drop hr{margin:0;border:0}.drop-top{height:17px;background:linear-gradient(${tint(on, .14)},${tint(on, .14)}) center/100% 1px no-repeat}
.drop-rule{height:13px;background:linear-gradient(${tint(on, .1)},${tint(on, .1)}) center/100% 1px no-repeat}
''';
}

/// The header menus' behavior. The wide panel opens 110 ms after the pointer
/// rests on its button and closes 180 ms after it leaves both, fading in
/// 190 ms; a click toggles it, Escape and a click outside the header close
/// it at once. It opens on its first section.
///
/// A section opens when the pointer enters its row, unless the pointer is on
/// its way to the open section's links (the move points between the
/// column's corners on the right, as Amazon's menu does): then it waits
/// 160 ms and looks again, so crossing a row on the way does not swap the
/// content. The column is a vertical tab list: arrows, Home and End move
/// through it and open what they reach. The compact list opens on click.
const headerMenuScript = r'''
(function () {
  var header = document.querySelector('header.top');
  if (!header) return;
  var slice = Array.prototype.slice;

  slice.call(header.querySelectorAll('[data-mega]')).forEach(function (item) {
    var btn = item.querySelector('.mega-btn');
    var panel = item.querySelector('.mega');
    var col = panel.querySelector('.mega-col');
    var tabs = slice.call(panel.querySelectorAll('.mega-sec'));
    var first = tabs.length ? tabs[0].dataset.branch : null;
    var open = false, closing = false, focused = false, suppress = false;
    var overButton = false, overPanel = false, focusIn = false;
    var openTimer = 0, closeTimer = 0, endTimer = 0, aimTimer = 0;
    var shown = null, moves = [], lastDelay = null;

    function busy() { return overButton || overPanel || focusIn; }

    function show(id, animate) {
      if (!id || id === shown) return;
      shown = id;
      tabs.forEach(function (tab) {
        var on = tab.dataset.branch === id;
        tab.classList.toggle('on', on);
        tab.setAttribute('aria-selected', on ? 'true' : 'false');
        tab.tabIndex = on ? 0 : -1;
      });
      slice.call(panel.querySelectorAll('.mega-branch[data-branch], .mega-photo')).forEach(function (el) {
        var on = el.dataset.branch === id;
        el.hidden = !on;
        el.classList.remove('enter');
        if (on && animate) { void el.offsetWidth; el.classList.add('enter'); }
      });
    }

    // The pointer is heading into the content when, seen from the column's
    // right corners, it moved closer to both since the last samples.
    function aiming() {
      if (!col || moves.length < 2) return false;
      var box = col.getBoundingClientRect();
      var now = moves[moves.length - 1], before = moves[0];
      if (lastDelay && now.x === lastDelay.x && now.y === lastDelay.y) return false;
      if (now.x >= box.right) return false;
      function slope(a, b) { return (b.y - a.y) / (b.x - a.x); }
      var up = { x: box.right, y: box.top - 40 }, down = { x: box.right, y: box.bottom + 40 };
      if (slope(now, up) < slope(before, up) && slope(now, down) > slope(before, down)) {
        lastDelay = now;
        return true;
      }
      return false;
    }

    function hover(id) {
      clearTimeout(aimTimer);
      if (aiming()) { aimTimer = setTimeout(function () { hover(id); }, 160); return; }
      show(id, true);
    }

    function fit() {
      var top = header.getBoundingClientRect().bottom;
      panel.style.maxHeight = Math.max(240, Math.min(600, innerHeight - top - 24)) + 'px';
    }

    function openPanel() {
      if (open) return;
      clearTimeout(openTimer); clearTimeout(closeTimer); clearTimeout(endTimer);
      open = true; closing = false;
      shown = null; moves = []; lastDelay = null;
      fit();
      item.classList.add('open');
      btn.setAttribute('aria-expanded', 'true');
      header.classList.add('mega-open');
      show(first, false);
      void panel.offsetWidth;
      item.classList.add('in');
    }

    function finish() {
      open = false; closing = false;
      clearTimeout(aimTimer);
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
      openTimer = setTimeout(function () { if (overButton || focused) openPanel(); }, 110);
    }

    function scheduleClose() {
      clearTimeout(openTimer); clearTimeout(closeTimer);
      closeTimer = setTimeout(requestClose, 180);
    }

    btn.addEventListener('mouseenter', function () { overButton = true; scheduleOpen(); });
    btn.addEventListener('mouseleave', function () { overButton = false; scheduleClose(); });
    btn.addEventListener('click', function () {
      if (open) { overButton = overPanel = focusIn = false; forceClose(); } else openPanel();
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
      if (event.key !== 'ArrowDown') return;
      event.preventDefault();
      openPanel();
      var on = panel.querySelector('.mega-sec.on');
      if (on) on.focus();
    });

    panel.addEventListener('mouseenter', function () {
      overPanel = true;
      clearTimeout(closeTimer);
      if (closing) reopen();
    });
    panel.addEventListener('mouseleave', function () { overPanel = false; scheduleClose(); });
    panel.addEventListener('mousemove', function (event) {
      moves.push({ x: event.clientX, y: event.clientY });
      if (moves.length > 3) moves.shift();
    });
    panel.addEventListener('focusin', function () { focusIn = true; clearTimeout(closeTimer); });
    panel.addEventListener('focusout', function (event) {
      if (panel.contains(event.relatedTarget)) return;
      focusIn = false;
      scheduleClose();
    });

    tabs.forEach(function (tab, index) {
      var id = tab.dataset.branch;
      tab.addEventListener('mouseenter', function () { hover(id); });
      tab.addEventListener('mouseleave', function () { clearTimeout(aimTimer); });
      tab.addEventListener('focus', function () { show(id, true); });
      tab.addEventListener('click', function () { clearTimeout(aimTimer); show(id, true); });
      tab.addEventListener('keydown', function (event) {
        var to = { ArrowDown: index + 1, ArrowUp: index - 1, Home: 0, End: tabs.length - 1 }[event.key];
        if (to === undefined) return;
        event.preventDefault();
        tabs[(to + tabs.length) % tabs.length].focus();
      });
    });

    panel.addEventListener('click', function (event) {
      var link = event.target.closest('a');
      if (!link || !panel.contains(link)) return;
      overButton = overPanel = focusIn = false;
      forceClose();
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
