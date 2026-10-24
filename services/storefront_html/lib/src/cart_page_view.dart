import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/cart_suggestions_copy.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

import 'cart_page_css.dart';
import 'cart_page_model.dart';
import 'material_icons.dart';
import 'site_layout.dart';

/// Where the cart page asks for its lines (`/carrito/lineas?l=<id>:<q>,…`).
const cartLinesPath = '/carrito/lineas';

/// `/carrito`, laid out like Flutter's `CartPage`. The basket lives in the
/// visitor's browser, so the server sends the frame (the empty state, the
/// heading, the summary's box) and the page's script asks
/// [cartLinesPath] for the lines, drawn here by [cartLinesJson] with the
/// same rules as Flutter's `CartProvider`.
Component cartPageDocument(PageContext page) {
  final theme = WebsiteThemeRoles.resolve(page.shell.setting);
  final key =
      'flutter.public_store_cart_v2.${base64Url.encode(utf8.encode(page.tenantId))}';
  return sitePage(
    context: page,
    meta: PageMeta(
      title: 'Carrito | ${page.shell.storeName}',
      description: 'Tu carrito de compras en ${page.shell.storeName}.',
      canonicalUrl: '${page.storeUrl}/carrito',
      indexable: false,
      styles: cartPageCss(theme),
    ),
    content: [
      div(
        classes: 'cart-page',
        attributes: {
          'data-cart': '',
          'data-lines-url': '${page.hidden ? '/_html' : ''}$cartLinesPath',
        },
        [
          div(classes: 'cart-in', [
            _empty(),
            div(
              classes: 'cart-full',
              attributes: {'data-cart-full': '', 'hidden': ''},
              [
                div(classes: 'cart-main', [
                  div(classes: 'cart-head', [
                    h1(classes: 'cart-title', [.text('Carrito de compras')]),
                    p(
                      classes: 'cart-units',
                      attributes: {'data-cart-units': ''},
                      const [],
                    ),
                    p(classes: 'cart-lead', [
                      .text(
                        'Ajusta cantidades y confirma disponibilidad antes de '
                        'continuar al pago.',
                      ),
                    ]),
                    div(
                      classes: 'cart-notice',
                      attributes: {
                        'data-cart-notice': '',
                        'hidden': '',
                        'role': 'status',
                      },
                      [
                        RawText(materialIcon(mdInfoOutline, size: 18)),
                        p(attributes: {'data-cart-notice-text': ''}, const []),
                        button(
                          attributes: {'type': 'button', 'data-act': 'ack'},
                          [.text('Entendido')],
                        ),
                      ],
                    ),
                  ]),
                  ul(
                    classes: 'cart-lines',
                    attributes: {'data-cart-lines': ''},
                    const [],
                  ),
                  Component.element(
                    tag: 'section',
                    classes: 'cart-more',
                    attributes: {
                      'data-cart-more': '',
                      'hidden': '',
                      'aria-labelledby': 'cart-more-title',
                    },
                    children: const [],
                  ),
                ]),
                Component.element(
                  tag: 'aside',
                  classes: 'cart-sum',
                  attributes: {
                    'data-cart-summary': '',
                    'aria-label': 'Resumen del pedido',
                  },
                  children: const [],
                ),
              ],
            ),
            p(
              classes: 'cart-wait',
              attributes: {'data-cart-loading': '', 'hidden': ''},
              [.text('Cargando tu carrito…')],
            ),
            p(
              classes: 'cart-failed',
              attributes: {'data-cart-failed': '', 'hidden': ''},
              [
                .text(
                  'No pudimos leer tu carrito en este navegador. Escríbenos por '
                  'WhatsApp y te ayudamos.',
                ),
              ],
            ),
            Component.element(
              tag: 'noscript',
              children: [
                p(classes: 'cart-failed', [
                  .text(
                    'Tu carrito se guarda en este navegador: activa JavaScript '
                    'para verlo.',
                  ),
                ]),
              ],
            ),
          ]),
          // Decides before the first paint whether there is anything to load,
          // so an empty cart never flashes «Cargando».
          script(content: _firstPaintScript(key)),
          Component.element(
            tag: 'dialog',
            classes: 'cart-dialog',
            attributes: {
              'data-cart-dialog': '',
              'aria-labelledby': 'cart-dialog-title',
            },
            children: [
              Component.element(
                tag: 'form',
                attributes: {'method': 'dialog'},
                children: [
                  h2(id: 'cart-dialog-title', [.text('Eliminar producto')]),
                  p(attributes: {'data-cart-dialog-text': ''}, const []),
                  div(classes: 'cart-dialog-acts', [
                    button(
                      classes: 'cart-dialog-no',
                      attributes: {'value': 'no'},
                      [.text('Cancelar')],
                    ),
                    button(
                      classes: 'cart-dialog-yes',
                      attributes: {'value': 'yes'},
                      [.text('Eliminar')],
                    ),
                  ]),
                ],
              ),
            ],
          ),
          p(
            classes: 'cart-toast',
            attributes: {'data-cart-toast': '', 'role': 'status', 'hidden': ''},
            [.text('Producto eliminado del carrito')],
          ),
        ],
      ),
    ],
    pageScripts: [script(content: cartPageScript)],
  );
}

Component _empty() => div(
  classes: 'cart-empty',
  attributes: {'data-cart-empty': '', 'hidden': ''},
  [
    span(classes: 'cart-empty-box', [
      RawText(materialIcon(mdCartOutlined, size: 62)),
    ]),
    h2(classes: 'cart-title', [.text('Tu carrito está vacío')]),
    p([
      .text(
        'Agrega productos para comenzar tu compra. El carro mantendrá las '
        'cantidades y el resumen mientras recorres la tienda.',
      ),
    ]),
    a(classes: 'cart-go', href: '/productos', [
      RawText(materialIcon(mdShoppingBagOutlined, size: 18)),
      .text('Explorar productos'),
    ]),
    a(classes: 'cart-home', href: '/', [.text('Volver al inicio')]),
  ],
);

String _firstPaintScript(String key) =>
    '(function(r){try{var raw=localStorage.getItem(${jsonEncode(key)});'
    'var d=raw&&JSON.parse(JSON.parse(raw));'
    'var some=d&&Array.isArray(d.lines)&&d.lines.length>0;'
    'r.querySelector(some?"[data-cart-loading]":"[data-cart-empty]").hidden=false'
    '}catch(e){}'
    '})(document.currentScript.previousElementSibling);';

const _escape = HtmlEscape();
String _e(String value) => _escape.convert(value);
String _money(num amount) => _e(ChileanUtils.formatCurrency(amount.toDouble()));

/// The answer to [cartLinesPath]: the lines and the summary drawn, the
/// units, and what the browser must save in place of what it sent (`lines`
/// with each product's `limit`, and the products that left in `gone`).
Map<String, Object?> cartLinesJson(CartLinesModel model) {
  final tax = model.taxSummary;
  final units = model.units;
  return {
    'units': units,
    'unitsText': '$units ${units == 1 ? 'unidad' : 'unidades'} en revisión',
    'adjusted': model.adjusted,
    'gone': model.gone,
    'lines': [
      for (final line in model.lines)
        {'id': line.product.id, 'q': line.quantity, 'limit': line.limit},
    ],
    'payable': tax.isValid,
    'items': [
      for (final (index, line) in model.lines.indexed)
        _lineHtml(line, first: index == 0),
    ].join(),
    'summary': _summaryHtml(model),
    'more': _moreHtml(model),
  };
}

String _photo(
  PublicCommerceProductProjection commerce,
  PublicImageThumbnail? copies, {
  required String sizes,
  required int iconSize,
}) {
  final photo = commerce.imageUrls.isEmpty ? '' : commerce.imageUrls.first;
  return photo.isEmpty
      ? materialIcon(mdPedalBikeOutlined, size: iconSize)
      : '<img src="${_e(copies?.smallestUrl ?? photo)}"'
            '${copies != null && copies.variants.isNotEmpty ? ' srcset="${_e(copies.srcset)}" sizes="$sizes"' : ''}'
            ' alt="" loading="lazy" decoding="async">';
}

/// «Te puede faltar» ([CartSuggestionsCopy]): what fits the cart, each one
/// added from its own button; nothing when there is none.
String _moreHtml(CartLinesModel model) {
  if (model.suggestions.isEmpty) return '';
  final kind = model.suggestionsKind;
  final cards = [
    for (final pick in model.suggestions)
      '<li class="cm" data-sid="${_e(pick.product.id)}" data-max="${pick.max}" '
          'data-price="${pick.commerce.price.round()}" data-title="${_e(pick.commerce.title)}" '
          'data-item-id="${_e(pick.commerce.sku.isNotEmpty ? pick.commerce.sku : pick.product.id)}">'
          '<a class="cm-shot" href="${_e(pick.path)}" tabindex="-1" aria-hidden="true">'
          '${_photo(pick.commerce, pick.thumbnail, sizes: '120px', iconSize: 32)}</a>'
          '<div class="cm-info">'
          '${pick.commerce.brand.isEmpty ? '' : '<p class="cm-brand">${_e(pick.commerce.brand)}</p>'}'
          '<a class="cm-name" href="${_e(pick.path)}">${_e(pick.commerce.title)}</a>'
          '<div class="cm-foot"><b class="cm-price">${_money(pick.commerce.price)}</b>'
          '<button class="cm-add" type="button" data-act="suggest" data-done="${_e(CartSuggestionsCopy.added)}" '
          'aria-label="${_e(CartSuggestionsCopy.add)} ${_e(pick.commerce.title)}">'
          '${materialIcon(mdAdd, size: 16)}<span data-cm-label>${_e(CartSuggestionsCopy.add)}</span></button>'
          '</div></div></li>',
  ];
  return '<p class="cm-eye">${_e(CartSuggestionsCopy.eyebrow)}</p>'
      '<h2 class="cm-title" id="cart-more-title">${_e(CartSuggestionsCopy.title(kind))}</h2>'
      '<p class="cm-note">${_e(CartSuggestionsCopy.note(kind))}</p>'
      '<ul class="cm-row">${cards.join()}</ul>';
}

String _lineHtml(CartLine line, {required bool first}) {
  final commerce = line.commerce;
  final image = _photo(
    commerce,
    line.thumbnail,
    sizes: '(max-width: 979px) 92px, 144px',
    iconSize: 42,
  );
  final pills = [
    if (commerce.brand.isNotEmpty) commerce.brand,
    if (commerce.categoryPath.isNotEmpty) commerce.categoryPath,
  ];
  final title = commerce.title;
  final each = '${_money(commerce.price)} c/u';
  final available = line.product.availableStockQuantity;
  return '<li class="cl${first ? ' first' : ''}" data-id="${_e(line.product.id)}" '
      'data-q="${line.quantity}" data-price="${commerce.price.round()}" '
      'data-limit="${line.limit ?? ''}" data-title="${_e(commerce.title)}" '
      'data-item-id="${_e(commerce.sku.isNotEmpty ? commerce.sku : line.product.id)}">'
      '<div class="cl-shot">$image</div>'
      '<div class="cl-info"><div class="cl-top"><div class="cl-id">'
      '${pills.isEmpty ? '' : '<div class="cl-pills">${pills.map((pill) => '<span>${_e(pill)}</span>').join()}</div>'}'
      '<a class="cl-title" href="${_e(line.path)}">${_e(title)}</a>'
      '<p class="cl-sku">SKU ${_e(commerce.sku)}</p></div>'
      '<button class="cl-x" type="button" data-act="remove" aria-label="Eliminar ${_e(commerce.title)}" title="Eliminar">'
      '${materialIcon(mdClose, size: 18)}</button></div>'
      '${line.short ? '<p class="cl-short">Stock insuficiente. Solo $available disponibles.</p>' : ''}'
      '<div class="cl-buy"><div class="cl-qty-box"><p class="cl-label">Cantidad</p>'
      '<div class="cl-qty">'
      '<button type="button" data-act="dec" aria-label="Quitar una unidad"${line.quantity > 1 ? '' : ' disabled'}>${materialIcon(mdRemove, size: 16)}</button>'
      '<output aria-live="polite">${line.quantity}</output>'
      '<button type="button" data-act="inc" aria-label="Agregar una unidad"${line.canIncrement ? '' : ' disabled'}>${materialIcon(mdAdd, size: 16)}</button>'
      '</div></div>'
      '<div class="cl-sub"><p class="cl-each m">$each</p><div class="cl-amount">'
      '<p class="cl-total" data-line-total>${_money(line.subtotal)}</p>'
      '<p class="cl-each d">$each</p></div></div>'
      '</div></div></li>';
}

String _summaryHtml(CartLinesModel model) {
  final tax = model.taxSummary;
  final gross = model.grossAmount;
  final perks = [
    'Envío a Chile continental',
    'Retiro en tienda sin costo',
    'Compra 100% segura',
    'Atención personalizada',
  ];
  return '<h2 class="cs-title">Resumen del pedido</h2>'
      '${tax.isValid ? '<p class="cs-row"><span>${_e(tax.netLabel)}</span><b>${_money(tax.netAmount)}</b></p>'
                '<p class="cs-row sec"><span>${_e(tax.ivaLabel)}</span><b>${_money(tax.taxAmount)}</b></p>' : '<p class="cs-warn">${_e(tax.checkoutBlockMessage ?? 'No podemos validar los impuestos de este carrito.')}</p>'}'
      '<hr class="cs-rule">'
      '<p class="cs-total"><span>${tax.isValid ? 'Total' : 'Total productos'}</span>'
      '<b>${gross == null ? '—' : _money(gross)}</b></p>'
      '${tax.isValid ? '<a class="cs-pay" href="/checkout" data-checkout>Proceder al pago</a>' : '<button class="cs-pay" type="button" disabled>Proceder al pago</button>'}'
      '<a class="cs-more" href="/productos">Seguir comprando</a>'
      '<hr class="cs-rule b">'
      '<ul class="cs-perks">${perks.map((perk) => '<li>${materialIcon(mdCheck, size: 16)}${_e(perk)}</li>').join()}</ul>';
}

/// The cart's own script, after the page script that owns the document
/// (`window.vinabikeCart`): it asks for the lines, saves back what the store
/// adjusted (as Flutter does when it restores a basket), and changes
/// quantities through the same lock and rules as «Agregar».
const cartPageScript = r'''
(function (root) {
  var cart = window.vinabikeCart;
  if (!root || !cart) return;
  function $(s) { return root.querySelector(s); }
  var list = $('[data-cart-lines]'), summary = $('[data-cart-summary]');
  var units = $('[data-cart-units]'), notice = $('[data-cart-notice]');
  var dialog = $('[data-cart-dialog]'), toast = $('[data-cart-toast]');
  var more = $('[data-cart-more]');
  var seq = 0, adjusted = 0, toastTimer = null;

  function show(state) {
    $('[data-cart-full]').hidden = state !== 'full';
    $('[data-cart-empty]').hidden = state !== 'empty';
    $('[data-cart-loading]').hidden = state !== 'loading';
    $('[data-cart-failed]').hidden = state !== 'failed';
    root.setAttribute('data-cart-ready', state);
  }

  function saved() { try { return cart.lines(); } catch (e) { return null; } }

  function money(n) { return '$ ' + Math.round(n).toLocaleString('es-CL'); }

  // Google Analytics: `view_cart` once the lines show, `add_to_cart` and
  // `remove_from_cart` for a unit more or less and a line taken out, each
  // line as `view_item` names its product.
  var viewed = false;
  function lineItem(line, q) {
    return { item_id: line.dataset.itemId || line.dataset.id, item_name: line.dataset.title, price: Number(line.dataset.price || 0), quantity: q };
  }
  function measure(name, items) {
    var m = window.vinabikeMeasure;
    if (!m || !items.length) return;
    m.track(name, { currency: 'CLP', value: items.reduce(function (sum, it) { return sum + it.price * it.quantity; }, 0), items: items });
  }

  // Flutter's «Ajustamos N producto(s)…»: it adds up until «Entendido».
  function paintNotice() {
    notice.hidden = adjusted === 0;
    if (adjusted > 0) {
      notice.querySelector('[data-cart-notice-text]').textContent = adjusted === 1
        ? 'Ajustamos 1 producto de tu carrito guardado porque cambió su disponibilidad.'
        : 'Ajustamos ' + adjusted + ' productos de tu carrito guardado porque cambió su disponibilidad.';
    }
  }

  function refresh() {
    var lines = saved();
    if (lines === null) { show('failed'); return; }
    if (!lines.length) { show('empty'); return; }
    var mine = ++seq;
    var q = lines.map(function (l) { return l.id + ':' + l.q; }).join(',');
    fetch(root.dataset.linesUrl + '?l=' + encodeURIComponent(q), { headers: { accept: 'application/json' }, cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error(String(r.status)); return r.json(); })
      .then(function (data) {
        if (mine !== seq) return;
        if (data.adjusted > 0) {
          adjusted += data.adjusted;
          var limits = {};
          data.lines.forEach(function (l) { limits[l.id] = l.limit; });
          cart.update(function (current) {
            return current.filter(function (l) { return data.gone.indexOf(l.id) < 0; }).map(function (l) {
              var limit = limits[l.id];
              return typeof limit === 'number' && l.q > limit ? { id: l.id, q: limit } : l;
            });
          }).then(cart.badge, function () {});
        }
        paintNotice();
        if (!data.lines.length) { show('empty'); return; }
        list.innerHTML = data.items;
        summary.innerHTML = data.summary;
        more.innerHTML = data.more || '';
        more.hidden = !data.more;
        units.textContent = data.unitsText;
        show('full');
        if (!viewed) {
          viewed = true;
          measure('view_cart', [].map.call(list.querySelectorAll('[data-id]'), function (line) { return lineItem(line, Number(line.dataset.q)); }));
        }
      })
      .catch(function () { if (mine === seq) show('failed'); });
  }

  // Shows the new quantity at once; the summary follows the server.
  function change(line, delta) {
    var id = line.dataset.id;
    var limit = line.dataset.limit === '' ? null : Number(line.dataset.limit);
    var next = Number(line.dataset.q) + delta;
    if (next < 1 || (limit !== null && next > limit)) return;
    line.dataset.q = String(next);
    line.querySelector('output').textContent = String(next);
    line.querySelector('[data-line-total]').textContent = money(Number(line.dataset.price) * next);
    line.querySelector('[data-act=dec]').disabled = next <= 1;
    line.querySelector('[data-act=inc]').disabled = limit !== null && next >= limit;
    // What the saved cart really changed by (another tab may have changed
    // it first) is what Google Analytics hears.
    var changedBy = 0;
    cart.update(function (current) {
      changedBy = 0;
      return current.map(function (l) {
        if (l.id !== id) return l;
        var q = l.q + delta;
        if (limit !== null && q > limit) q = limit;
        if (q < 1) q = 1;
        changedBy = q - l.q;
        return { id: l.id, q: q };
      });
    }).then(function () {
      if (changedBy) measure(changedBy > 0 ? 'add_to_cart' : 'remove_from_cart', [lineItem(line, Math.abs(changedBy))]);
      cart.badge(); refresh();
    }, function () { show('failed'); });
  }

  // «Te puede faltar»: one unit in, then the cart draws it as a line.
  function suggest(button) {
    var pick = button.closest('[data-sid]');
    if (!pick || !cart.add) return;
    button.disabled = true;
    cart.add(pick.dataset.sid, 1, Number(pick.dataset.max || 0)).then(function (added) {
      if (added > 0) {
        var item = { item_id: pick.dataset.itemId || pick.dataset.sid, item_name: pick.dataset.title, price: Number(pick.dataset.price || 0), quantity: added };
        measure('add_to_cart', [item]);
        var m = window.vinabikeMeasure;
        if (m && m.pixel) m.pixel('AddToCart', { content_ids: [item.item_id], content_name: item.item_name, content_type: 'product', value: item.price * added, currency: 'CLP' });
        button.classList.add('is-done');
        var label = button.querySelector('[data-cm-label]');
        if (label) label.textContent = button.dataset.done;
      }
      cart.badge();
      refresh();
    }, function () { button.disabled = false; });
  }

  var removing = null;
  function askRemove(line) {
    removing = line;
    dialog.querySelector('[data-cart-dialog-text]').textContent =
      '¿Estás seguro que deseas eliminar "' + line.dataset.title + '" del carrito?';
    if (dialog.showModal) dialog.showModal(); else if (confirm(dialog.querySelector('[data-cart-dialog-text]').textContent)) remove();
  }
  function remove() {
    var line = removing; removing = null;
    if (!line) return;
    var id = line.dataset.id, removedQ = 0;
    cart.update(function (current) {
      removedQ = 0;
      return current.filter(function (l) { if (l.id !== id) return true; removedQ = l.q; return false; });
    })
      .then(function () {
        if (removedQ) measure('remove_from_cart', [lineItem(line, removedQ)]);
        cart.badge();
        toast.hidden = false;
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { toast.hidden = true; }, 2000);
        refresh();
      }, function () { show('failed'); });
  }
  dialog.addEventListener('close', function () {
    if (dialog.returnValue === 'yes') remove(); else removing = null;
  });

  root.addEventListener('click', function (event) {
    var button = event.target.closest && event.target.closest('[data-act]');
    if (!button || button.disabled) return;
    var act = button.dataset.act;
    if (act === 'ack') { adjusted = 0; paintNotice(); return; }
    if (act === 'suggest') { suggest(button); return; }
    var line = button.closest('[data-id]');
    if (!line) return;
    if (act === 'inc') change(line, 1);
    else if (act === 'dec') change(line, -1);
    else if (act === 'remove') askRemove(line);
  });

  window.addEventListener('storage', function (event) { if (event.key === cart.key) refresh(); });
  window.addEventListener('pageshow', function (event) { if (event.persisted) refresh(); });
  refresh();
})(document.querySelector('[data-cart]'));
''';
