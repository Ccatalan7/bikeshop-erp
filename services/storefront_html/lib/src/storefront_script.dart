/// The one script every HTML page loads at the end of the body. Without it
/// the pages are complete; it adds what needs the browser:
///
/// - **Cart.** «Agregar al carrito» writes the document the Flutter cart reads
///   (`lib/public_store/services/cart_store.dart`): localStorage key
///   `flutter.public_store_cart_v2.<base64url(tenant)>`, a JSON string holding
///   `{v: 1, tenant, saved_at, lines: [{id, q}], revision, applied_mutations}`,
///   written under the same Web Lock (`vinabike.public_store_cart.storage.v2`)
///   and discarded after seven days, like Flutter. Only ids and quantities are
///   stored; Flutter re-reads price and stock when it restores the cart.
/// - **Measurement.** `view_item`, `add_to_cart`, `contact` and `store_ready`
///   with the parameters `ga4_commerce_events.dart` sends, and the Meta Pixel's
///   `ViewContent`/`AddToCart`, only where the head allowed measuring.
/// - **Photos and filters.** The thumbnails switch the main photo; a filter or
///   an order applies itself when it changes (the forms also submit without
///   JavaScript).
const storefrontScript = r'''
(function () {
  document.documentElement.classList.add('js');
  var body = document.body;
  var tenant = body.dataset.tenant || '';
  var cartKey = body.dataset.cartKey || '';
  var lockName = 'vinabike.public_store_cart.storage.v2';
  var maxAge = 7 * 864e5;
  var futureSkew = 5 * 6e4;

  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16);
    crypto.getRandomValues(b);
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    var h = Array.prototype.map.call(b, function (x) { return (x + 256).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }

  function fresh(iso, now) {
    var t = Date.parse(iso);
    return isFinite(t) && t <= now + futureSkew && now - t <= maxAge;
  }

  // `public_store_cart_v1`, the key every store shared before the cart was
  // kept per store. Flutter moves a document of this store from there on its
  // next read; the page does the same when it writes (Codex, 2026-10-05: an
  // add here used to hide that basket from Flutter).
  var legacyKey = 'flutter.public_store_cart_v1';

  function decode(raw) {
    var inner = JSON.parse(raw);
    if (typeof inner !== 'string') throw new Error('cart');
    var doc = JSON.parse(inner);
    if (!doc || doc.v !== 1 || typeof doc.tenant !== 'string' || !Array.isArray(doc.lines)) throw new Error('cart');
    return doc;
  }

  // The stored cart of this store, or null when there is none or it is older
  // than seven days. A document Flutter could not read is never touched: the
  // add fails instead of overwriting the visitor's basket. `legacy` says the
  // old shared key held it (or held this store's expired basket).
  function readCart(now) {
    var raw = localStorage.getItem(cartKey);
    if (raw) {
      var doc = decode(raw);
      if (doc.tenant.trim() !== tenant) throw new Error('cart');
      return { doc: fresh(doc.saved_at, now) ? doc : null, legacy: false };
    }
    var old = localStorage.getItem(legacyKey);
    if (!old) return { doc: null, legacy: false };
    var legacyDoc = decode(old);
    // Another store's basket stays where it is.
    if (legacyDoc.tenant.trim() !== tenant) return { doc: null, legacy: false };
    return { doc: fresh(legacyDoc.saved_at, now) ? legacyDoc : null, legacy: true };
  }

  function cartCount() {
    try {
      var doc = readCart(Date.now()).doc;
      return doc ? doc.lines.reduce(function (sum, line) { return sum + (line.q || 0); }, 0) : 0;
    } catch (e) { return 0; }
  }

  function paintBadge() {
    var n = cartCount();
    document.querySelectorAll('[data-cart-count]').forEach(function (el) {
      el.textContent = n > 99 ? '99+' : String(n);
      el.hidden = n === 0;
    });
  }

  // Saves [lines] as the next document, under the lock the caller holds.
  // The ids of writes already applied keep a retried write from applying
  // twice. Flutter still reads the first encoding, a bare id dated by the
  // document; it is kept, as `{id, at}`.
  function commit(stored, lines, now) {
    var doc = stored.doc;
    var at = new Date(now).toISOString();
    var applied = ((doc && doc.applied_mutations) || []).map(function (m) {
      if (typeof m === 'string') return { id: m.trim(), at: doc.saved_at };
      return m && typeof m === 'object' ? { id: String(m.id || '').trim(), at: m.at } : null;
    }).filter(function (m) {
      return m && m.id && fresh(m.at, now);
    });
    applied.push({ id: uuid(), at: at });
    var next = { v: 1, tenant: tenant, saved_at: at, lines: lines, revision: uuid(), applied_mutations: applied };
    var encoded = JSON.stringify(JSON.stringify(next));
    localStorage.setItem(cartKey, encoded);
    if (localStorage.getItem(cartKey) !== encoded) throw new Error('cart');
    // The write is done: the store's own key is the one Flutter reads first,
    // so a failure to clear the old shared key must not report it as lost
    // (a retry would add the units twice).
    if (stored.legacy) {
      try { localStorage.removeItem(legacyKey); } catch (e) { /* read first anyway */ }
    }
  }

  function locked(run) {
    if (navigator.locks && navigator.locks.request) {
      return navigator.locks.request(lockName, function () { return run(); });
    }
    return Promise.resolve().then(run);
  }

  function copyLines(doc) {
    return doc ? doc.lines.map(function (l) { return { id: l.id, q: l.q }; }) : [];
  }

  function addToCart(id, quantity, max) {
    return locked(function () {
      var now = Date.now();
      var stored = readCart(now);
      var lines = copyLines(stored.doc);
      var line = lines.filter(function (l) { return l.id === id; })[0];
      var wanted = (line ? line.q : 0) + quantity;
      var bounded = max > 0 ? Math.min(wanted, max) : wanted;
      if (bounded < 1) return 0;
      if (line) line.q = bounded; else lines.push({ id: id, q: bounded });
      commit(stored, lines, now);
      return bounded - (line ? wanted - quantity : 0);
    });
  }

  // The cart page changes the same document: [change] gets the saved lines
  // and returns the ones to keep (a line under one unit leaves). Nothing is
  // written when they are the same.
  function updateCart(change) {
    return locked(function () {
      var now = Date.now();
      var stored = readCart(now);
      var before = copyLines(stored.doc);
      var lines = change(copyLines(stored.doc)).filter(function (l) {
        return l && l.id && l.q >= 1 && l.q === Math.floor(l.q);
      });
      if (JSON.stringify(lines) === JSON.stringify(before)) return lines;
      commit(stored, lines, now);
      return lines;
    });
  }

  // The checkout needs the saved document's revision (Flutter's
  // `captureDurableCheckoutRevision`): a document without one (written
  // before revisions) is saved again first, with the same lines.
  function ensureRevision() {
    return locked(function () {
      var now = Date.now();
      var stored = readCart(now);
      if (stored.doc && (!stored.doc.revision || stored.legacy)) {
        commit(stored, copyLines(stored.doc), now);
        stored = readCart(now);
      }
      var doc = stored.doc;
      return { lines: copyLines(doc), revision: doc && doc.revision ? String(doc.revision) : null };
    });
  }

  // `consumeOrderedLines`: after an order, the cart loses what was ordered,
  // only if it is still the document the order was made from (its
  // revision); otherwise it stays as it is and the order page says so.
  function consumeLines(ordered, expectedRevision) {
    return locked(function () {
      var now = Date.now();
      var stored = readCart(now);
      var doc = stored.doc;
      if (!doc || stored.legacy || !expectedRevision || String(doc.revision || '') !== String(expectedRevision)) return false;
      var want = {};
      for (var i = 0; i < ordered.length; i++) {
        var id = String(ordered[i].id || '').trim(), q = ordered[i].q;
        if (!id || !(q >= 1)) return false;
        want[id] = (want[id] || 0) + q;
      }
      var lines = copyLines(doc).map(function (l) { return { id: l.id, q: l.q - (want[l.id] || 0) }; })
        .filter(function (l) { return l.q > 0; });
      var applied = ((doc.applied_mutations) || []).map(function (m) {
        if (typeof m === 'string') return { id: m.trim(), at: doc.saved_at };
        return m && typeof m === 'object' ? { id: String(m.id || '').trim(), at: m.at } : null;
      }).filter(function (m) { return m && m.id && fresh(m.at, now); });
      var next = { v: 1, tenant: tenant, saved_at: new Date(now).toISOString(), lines: lines, revision: uuid() };
      if (applied.length) next.applied_mutations = applied;
      var encoded = JSON.stringify(JSON.stringify(next));
      localStorage.setItem(cartKey, encoded);
      if (localStorage.getItem(cartKey) !== encoded) throw new Error('cart');
      return true;
    });
  }

  window.vinabikeCart = {
    key: cartKey,
    // The saved lines, `[]` without a cart; throws on a document Flutter
    // could not read, which is never overwritten.
    lines: function () { return copyLines(readCart(Date.now()).doc); },
    update: updateCart,
    ensureRevision: ensureRevision,
    consume: consumeLines,
    badge: function () { paintBadge(); }
  };

  function track(name, params) {
    if (!window.vinabikeMeasurementAllowed) return;
    if (typeof window.gtag === 'function') window.gtag('event', name, params);
  }

  function pixel(name, params) {
    if (!window.vinabikeMeasurementAllowed || typeof window.fbq !== 'function') return;
    window.fbq('track', name, params);
  }

  // For the checkout's `begin_checkout` and `InitiateCheckout`.
  window.vinabikeMeasure = { track: track, pixel: pixel };

  var prefetched = false;
  function warmCart() {
    // The cart is still the Flutter store: start fetching it once the visitor
    // shows the intent, never on a plain visit.
    if (prefetched) return;
    prefetched = true;
    var link = document.createElement('link');
    link.rel = 'prefetch';
    link.href = '/main.dart.js';
    document.head.appendChild(link);
  }

  function itemOf(el) {
    return {
      item_id: el.dataset.itemId,
      item_name: el.dataset.itemName,
      price: Number(el.dataset.price || 0),
      quantity: 1
    };
  }

  var product = document.querySelector('[data-product-id]');
  if (product) {
    var item = itemOf(product);
    track('view_item', { currency: 'CLP', value: item.price, items: [item] });
    pixel('ViewContent', { content_ids: [item.item_id], content_name: item.item_name, content_type: 'product', value: item.price, currency: 'CLP' });
  }

  var addButton = document.querySelector('form.cart button.add');
  var addLabel = addButton && addButton.querySelector('[data-add-label]');
  var doneTimer = null;

  function inCart() {
    try {
      var doc = readCart(Date.now()).doc;
      return !!(doc && product && doc.lines.some(function (l) { return l.id === product.dataset.productId && l.q > 0; }));
    } catch (e) { return false; }
  }

  // Flutter's buy column: «Ya tienes este producto en el carrito.» with «Ver
  // carrito», and the button offers «Añadir otra unidad».
  function showInCart() {
    var note = document.getElementById('cart-note');
    if (!note || !inCart()) return;
    note.hidden = false;
    note.dataset.state = 'in';
    note.querySelector('[data-note-text]').textContent = 'Ya tienes este producto en el carrito.';
    if (addLabel && !(addButton.classList.contains('is-done'))) addLabel.textContent = 'Añadir otra unidad';
  }
  showInCart();

  function onAdd(event, then) {
    event.preventDefault();
    if (!product) return;
    var qtyInput = document.querySelector('form.cart input[name=cantidad]');
    var quantity = Math.max(1, Math.floor(Number(qtyInput ? qtyInput.value : 1) || 1));
    var note = document.getElementById('cart-note');
    var max = Number(product.dataset.max || 0);
    addToCart(product.dataset.productId, quantity, max).then(function (added) {
      paintBadge();
      if (added > 0) {
        var item = itemOf(product);
        item.quantity = added;
        track('add_to_cart', { currency: 'CLP', value: item.price * added, items: [item] });
        pixel('AddToCart', { content_ids: [item.item_id], content_name: item.item_name, content_type: 'product', value: item.price * added, currency: 'CLP' });
        warmCart();
        if (qtyInput) qtyInput.value = '1';
      }
      if (then === 'checkout' && (added > 0 || inCart())) {
        location.href = '/checkout';
        return;
      }
      if (added > 0 && addButton) {
        // The button itself acknowledges the click, where the eye already is.
        addButton.classList.add('is-done');
        if (addLabel) addLabel.textContent = 'Agregado al carrito';
        clearTimeout(doneTimer);
        doneTimer = setTimeout(function () {
          addButton.classList.remove('is-done');
          showInCart();
        }, 2600);
      }
      if (note) {
        note.hidden = false;
        note.dataset.state = added > 0 ? 'in' : 'max';
        note.querySelector('[data-note-text]').textContent = added > 0
          ? 'Ya tienes este producto en el carrito.'
          : 'Ya tienes en el carrito todo el stock disponible.';
      }
    }).catch(function () {
      if (note) {
        note.hidden = false;
        note.dataset.state = 'error';
        note.querySelector('[data-note-text]').textContent =
          'No pudimos guardar tu carrito en este navegador. Escríbenos por WhatsApp y te ayudamos.';
      }
    });
  }

  document.querySelectorAll('form.cart').forEach(function (form) {
    form.addEventListener('submit', function (e) {
      var submitter = e.submitter;
      onAdd(e, submitter && submitter.hasAttribute('data-buy-now') ? 'checkout' : null);
    });
  });
  // The − and + of the quantity, bounded like Flutter's selector.
  document.querySelectorAll('form.cart [data-step]').forEach(function (step) {
    step.addEventListener('click', function () {
      var input = document.querySelector('form.cart input[name=cantidad]');
      if (!input) return;
      var max = Number(input.max || 0);
      var next = (Math.floor(Number(input.value) || 1)) + Number(step.dataset.step);
      if (next < 1) next = 1;
      if (max > 0 && next > max) next = max;
      input.value = String(next);
    });
  });

  document.querySelectorAll('.thumbs button').forEach(function (thumb) {
    thumb.addEventListener('click', function () {
      var photo = document.getElementById('foto');
      if (!photo) return;
      photo.removeAttribute('srcset');
      photo.src = thumb.dataset.src;
      document.querySelectorAll('.thumbs button').forEach(function (other) { other.removeAttribute('aria-current'); });
      thumb.setAttribute('aria-current', 'true');
    });
  });

  // Filters and order apply when they change; the button stays for no-JS.
  // A price waits for its own button. Empty fields stay out of the URL.
  document.querySelectorAll('form').forEach(function (form) {
    if ((form.method || '').toLowerCase() !== 'get') return;
    form.addEventListener('submit', function () {
      form.querySelectorAll('input[name]').forEach(function (input) {
        if (input.value === '' && input.type !== 'checkbox') {
          input.disabled = true;
          input.setAttribute('data-was-empty', '');
        }
      });
    });
    if (!form.hasAttribute('data-autosubmit')) return;
    form.addEventListener('change', function (event) {
      if (event.target && event.target.hasAttribute('data-manual')) return;
      if (form.requestSubmit) form.requestSubmit(); else form.submit();
    });
  });
  // The header's search icon leads to `#buscar`, which on a phone sits in the
  // closed filters panel: open it and put the cursor there.
  function openSearch() {
    if (location.hash !== '#buscar') return;
    var toggle = document.getElementById('filtros');
    if (toggle) toggle.checked = true;
    var input = document.getElementById('buscar');
    if (input) input.focus();
  }
  openSearch();
  window.addEventListener('hashchange', openSearch);

  // Back from the results the page may come from the cache with those fields
  // still disabled.
  window.addEventListener('pageshow', function () {
    document.querySelectorAll('input[data-was-empty]').forEach(function (input) {
      input.disabled = false;
      input.removeAttribute('data-was-empty');
    });
    closeSheets();
  });

  // The phone's sheets (menu, filters, order) are checkboxes: Escape closes
  // them, and so does coming back to the page.
  function closeSheets() {
    document.querySelectorAll('#menu-toggle:checked, .sheet-check:checked').forEach(function (box) {
      box.checked = false;
    });
  }
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') closeSheets();
  });

  // Same classification as Ga4CommerceEvents.contactMethodFor.
  function contactMethod(href) {
    var url;
    try { url = new URL(href, location.href); } catch (e) { return null; }
    var scheme = url.protocol.replace(':', '').toLowerCase();
    var host = url.hostname.toLowerCase();
    var path = url.pathname.toLowerCase();
    if (scheme === 'tel') return 'phone';
    if (scheme === 'mailto') return 'email';
    if (scheme === 'whatsapp' || host === 'wa.me' || /(^|\.)whatsapp\.com$/.test(host)) return 'whatsapp';
    if (host === 'maps.app.goo.gl' || host.indexOf('maps.google.') === 0 ||
        (/google\.(com|cl)$/.test(host) && path.indexOf('/maps') === 0)) return 'directions';
    return null;
  }
  document.addEventListener('click', function (event) {
    var link = event.target.closest && event.target.closest('a[href]');
    if (!link) return;
    var method = contactMethod(link.getAttribute('href'));
    if (method) track('contact', { method: method });
  });

  // `store_ready` as the Flutter store reports it: seconds until the page is
  // usable, with the same buckets (Ga4CommerceEvents.storeReadyBucket).
  window.addEventListener('load', function () {
    var nav = performance.getEntriesByType && performance.getEntriesByType('navigation')[0];
    var ms = Math.round(nav ? nav.domContentLoadedEventEnd : performance.now());
    if (ms <= 0) return;
    var bucket = ms <= 2500 ? 'bueno_hasta_2_5s' : ms <= 4000 ? 'mejorable_hasta_4s' : ms <= 8000 ? 'lento_hasta_8s' : 'muy_lento_mas_de_8s';
    track('store_ready', { value: Math.round(ms / 100) / 10, load_ms: ms, load_bucket: bucket });
  });

  paintBadge();
  window.addEventListener('storage', function (event) { if (event.key === cartKey) paintBadge(); });
  window.addEventListener('pageshow', paintBadge);
})();
''';
