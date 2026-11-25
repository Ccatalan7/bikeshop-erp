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
///   with the parameters `ga4_commerce_events.dart` sends, `view_item_list`
///   and `select_item` for the lists of cards, and the Meta Pixel's
///   `ViewContent`/`AddToCart`, only where the head allowed measuring.
/// - **Photos and filters.** A product's photos slide sideways and the
///   thumbnails follow them (they slide the row without JavaScript too, by
///   finger or trackpad); a filter or an order applies itself when it
///   changes (the forms also submit without JavaScript).
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
    // `add(id, q, max)`: what «Agregar» does, the units it put in.
    add: addToCart,
    ensureRevision: ensureRevision,
    consume: consumeLines,
    badge: function () { paintBadge(); }
  };

  function track(name, params) {
    if (!window.vinabikeMeasurementAllowed) return;
    if (typeof window.gtag === 'function') window.gtag('event', name, params);
  }

  // `eventId` lets Meta discard a repeat (`purchase_<order>`).
  function pixel(name, params, eventId) {
    if (!window.vinabikeMeasurementAllowed || typeof window.fbq !== 'function') return;
    if (eventId) window.fbq('track', name, params, { eventID: eventId });
    else window.fbq('track', name, params);
  }

  // For the checkout's `begin_checkout` and `InitiateCheckout` and the
  // order page's `purchase`.
  window.vinabikeMeasure = { track: track, pixel: pixel };

  // A search the store showed nothing for (`/buscar/sin-resultados`,
  // 2026-10-24): the ERP's «Búsquedas» shows what people look for and do not
  // find. Only the words, once per visit and with no identity: it is not
  // measurement, so it does not wait on the consent.
  function searchMiss(q) {
    q = String(q || '').trim();
    if (q.length < 2 || q.length > 80) return;
    var key = 'vb-search-misses', sent = [];
    try { sent = JSON.parse(sessionStorage.getItem(key) || '[]'); } catch (e) { sent = []; }
    if (!Array.isArray(sent)) sent = [];
    var folded = q.toLowerCase();
    if (sent.indexOf(folded) >= 0) return;
    sent.push(folded);
    try { sessionStorage.setItem(key, JSON.stringify(sent.slice(-50))); } catch (e) { /* once on this page */ }
    var body = new URLSearchParams({ q: q });
    try { if (navigator.sendBeacon && navigator.sendBeacon('/buscar/sin-resultados', body)) return; } catch (e) { /* the fetch below */ }
    fetch('/buscar/sin-resultados', { method: 'POST', body: body, keepalive: true }).catch(function () {});
  }
  window.vinabikeSearchMiss = searchMiss;
  var missed = document.querySelector('[data-search-miss]');
  if (missed) searchMiss(missed.dataset.searchMiss);

  // Lists of products (`[data-list-id]`: a catalog, a products block, the
  // related ones): `view_item_list` for each one shown, `select_item` when
  // a card is opened, its cards as `view_item` names a product plus their
  // place in the list. A copy a band hides is not shown.
  function listCards(list) { return [].slice.call(list.querySelectorAll('a[data-item-id]')); }
  function listItem(list, a, index) {
    return {
      item_id: a.dataset.itemId,
      item_name: a.dataset.itemName,
      price: Number(a.dataset.price || 0),
      index: index,
      item_list_id: list.dataset.listId,
      item_list_name: list.dataset.listName
    };
  }
  // [root]: the page, or the part another size or color brought.
  function measureLists(root) {
    [].forEach.call(root.querySelectorAll('[data-list-id]'), function (list) {
      if (!list.getClientRects().length) return;
      var items = listCards(list).map(function (a, i) { return listItem(list, a, i); });
      if (items.length) track('view_item_list', { item_list_id: list.dataset.listId, item_list_name: list.dataset.listName, items: items.slice(0, 200) });
    });
  }
  measureLists(document);
  document.addEventListener('click', function (event) {
    var a = event.target.closest && event.target.closest('a[data-item-id]');
    var list = a && a.closest('[data-list-id]');
    if (!list) return;
    track('select_item', { item_list_id: list.dataset.listId, item_list_name: list.dataset.listName, items: [listItem(list, a, listCards(list).indexOf(a))] });
  });

  function itemOf(el) {
    return {
      item_id: el.dataset.itemId,
      item_name: el.dataset.itemName,
      price: Number(el.dataset.price || 0),
      quantity: 1
    };
  }

  // The product the page shows: the first element with a product id (the
  // cards of what fits and the question sheet come after it). Read each
  // time: another size or color updates it where it is (2026-11-21).
  // A card's «Agregar» button carries a product id too and is never the
  // page's product: the home, with a products block and no product of its
  // own, sent `view_item` and `ViewContent` for its first card on every
  // visit (281 of 764 `view_item` from 27-oct to 23-nov, 2026-11-24).
  function productEl() { return document.querySelector('[data-product-id]:not([data-quick-add])'); }
  function addButtonEl() { return document.querySelector('form.cart button.add'); }
  function barEl() { return document.querySelector('[data-buybar]'); }

  // A model's sizes and colors change the page where it is (below): the
  // page as it came is kept, before anything here touches it, to come back
  // to it without asking again.
  var parts = {};
  var switching = !!(document.querySelector('.variant-picker') && window.fetch && window.DOMParser);
  if (switching) {
    var landed = document.getElementById('contenido');
    var landedQuestion = document.querySelector('[data-question]');
    var landedCanonical = document.querySelector('link[rel=canonical]');
    if (landed) {
      parts[location.pathname] = Promise.resolve({
        title: document.title,
        canonical: landedCanonical ? landedCanonical.getAttribute('href') : '',
        main: landed.cloneNode(true),
        question: landedQuestion ? landedQuestion.cloneNode(true) : null
      });
    }
  }

  // `view_item` and `ViewContent` for the product in sight: on arrival and
  // for each size or color chosen, as when each one was its own visit.
  function viewProduct() {
    var product = productEl();
    if (!product) return;
    var item = itemOf(product);
    track('view_item', { currency: 'CLP', value: item.price, items: [item] });
    pixel('ViewContent', { content_ids: [item.item_id], content_name: item.item_name, content_type: 'product', value: item.price, currency: 'CLP' });
  }
  viewProduct();

  var doneTimer = null;
  var barIdle = '';
  // The phone's buy bar: shown while the form's button is out of sight
  // (2026-10-24). Another size or color brings its own bar and form: the
  // watch moves to them.
  var phone = window.matchMedia ? window.matchMedia('(max-width:767px)') : null;
  var inSight = true;
  var watch = null;
  function paintBar() {
    var bar = barEl();
    var show = !!(bar && phone && phone.matches && !inSight);
    if (bar) bar.hidden = !show;
    document.documentElement.classList.toggle('has-buybar', show);
  }
  function watchBar() {
    var bar = barEl(), add = addButtonEl();
    if (watch) watch.disconnect();
    var label = bar && bar.querySelector('[data-buybar-label]');
    if (label) barIdle = label.textContent;
    if (bar && add && phone && 'IntersectionObserver' in window) {
      watch = watch || new IntersectionObserver(function (entries) {
        inSight = entries[entries.length - 1].isIntersecting;
        paintBar();
      });
      watch.observe(add);
    }
    paintBar();
  }
  if (barEl()) watchBar();
  if (phone && phone.addEventListener && productEl()) phone.addEventListener('change', paintBar);

  function inCart() {
    try {
      var doc = readCart(Date.now()).doc, product = productEl();
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
    var add = addButtonEl(), label = add && add.querySelector('[data-add-label]');
    if (label && !add.classList.contains('is-done')) label.textContent = 'Añadir otra unidad';
  }
  showInCart();

  // Puts the page's product in the cart with the form's quantity and says so
  // on its buttons and its note; [then] 'checkout' goes on to pay. Answers
  // the units it put in: 0 when the stock was already in the cart, -1 when
  // this browser keeps no cart.
  function addCurrent(then) {
    var product = productEl();
    if (!product) return Promise.resolve(0);
    var qtyInput = document.querySelector('form.cart input[name=cantidad]');
    var quantity = Math.max(1, Math.floor(Number(qtyInput ? qtyInput.value : 1) || 1));
    var note = document.getElementById('cart-note');
    var addButton = addButtonEl();
    var addLabel = addButton && addButton.querySelector('[data-add-label]');
    var bar = barEl();
    var barButton = bar && bar.querySelector('[data-buybar-add]');
    var barLabel = bar && bar.querySelector('[data-buybar-label]');
    var item = itemOf(product);
    return addToCart(product.dataset.productId, quantity, Number(product.dataset.max || 0)).then(function (added) {
      paintBadge();
      if (added > 0) {
        item.quantity = added;
        track('add_to_cart', { currency: 'CLP', value: item.price * added, items: [item] });
        pixel('AddToCart', { content_ids: [item.item_id], content_name: item.item_name, content_type: 'product', value: item.price * added, currency: 'CLP' });
        if (qtyInput) qtyInput.value = '1';
      }
      if (then === 'checkout' && (added > 0 || inCart())) {
        location.href = '/checkout';
        return added;
      }
      if (added > 0 && addButton) {
        // The button itself acknowledges the click, where the eye already is.
        addButton.classList.add('is-done');
        if (addLabel) addLabel.textContent = 'Agregado al carrito';
        if (barButton) barButton.classList.add('is-done');
        if (barLabel) barLabel.textContent = 'Agregado';
        clearTimeout(doneTimer);
        doneTimer = setTimeout(function () {
          addButton.classList.remove('is-done');
          if (barButton) barButton.classList.remove('is-done');
          if (barLabel) barLabel.textContent = barIdle;
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
      return added;
    }).catch(function () {
      if (note) {
        note.hidden = false;
        note.dataset.state = 'error';
        note.querySelector('[data-note-text]').textContent =
          'No pudimos guardar tu carrito en este navegador. Escríbenos por WhatsApp y te ayudamos.';
      }
      return -1;
    });
  }

  // The cart's form, bound where it is: another size or color brings a new
  // one, bound the same way (the cart contract test drives this binding).
  function bindCartForms() {
    document.querySelectorAll('form.cart').forEach(function (form) {
      if (form.vbBound) return;
      form.vbBound = true;
      form.addEventListener('submit', function (e) {
        e.preventDefault();
        var submitter = e.submitter;
        addCurrent(submitter && submitter.hasAttribute('data-buy-now') ? 'checkout' : null);
      });
    });
  }
  bindCartForms();

  // The bar's button: the layer to choose in when the product comes in
  // sizes or colors (owner, 2026-11-21: «te abre una nueva capa y te
  // elige»), otherwise the form's own button.
  document.addEventListener('click', function (event) {
    var button = event.target.closest && event.target.closest('[data-buybar-add]');
    if (!button) return;
    var product = productEl();
    if (opts && opts.showModal && product && product.querySelector('.variant-picker')) {
      openOptions();
      return;
    }
    var add = addButtonEl();
    if (add) add.click();
  });

  // «Lo que va con esto»: each fitting product is added from its own button,
  // which says so where the eye is (2026-10-23).
  document.addEventListener('click', function (event) {
    var button = event.target.closest && event.target.closest('[data-quick-add]');
    if (!button || button.disabled) return;
    var label = button.querySelector('[data-quick-label]');
    button.disabled = true;
    addToCart(button.dataset.productId, 1, Number(button.dataset.max || 0)).then(function (added) {
      paintBadge();
      if (added > 0) {
        var item = { item_id: button.dataset.itemId, item_name: button.dataset.itemName, price: Number(button.dataset.price || 0), quantity: added };
        track('add_to_cart', { currency: 'CLP', value: item.price * added, items: [item] });
        pixel('AddToCart', { content_ids: [item.item_id], content_name: item.item_name, content_type: 'product', value: item.price * added, currency: 'CLP' });
        button.classList.add('is-done');
        if (label) label.textContent = 'En el carrito';
      } else if (label) {
        label.textContent = 'Sin más stock';
      }
      clearTimeout(button.vbTimer);
      button.vbTimer = setTimeout(function () {
        button.classList.remove('is-done');
        if (label) label.textContent = 'Agregar';
        button.disabled = false;
      }, 2600);
    }).catch(function () {
      button.disabled = false;
      if (label) label.textContent = 'No se pudo';
    });
  });
  // The − and + of the quantity, bounded like Flutter's selector.
  document.addEventListener('click', function (event) {
    var step = event.target.closest && event.target.closest('form.cart [data-step]');
    if (!step) return;
    var input = document.querySelector('form.cart input[name=cantidad]');
    if (!input) return;
    var max = Number(input.max || 0);
    var next = (Math.floor(Number(input.value) || 1)) + Number(step.dataset.step);
    if (next < 1) next = 1;
    if (max > 0 && next > max) next = max;
    input.value = String(next);
  });

  // The product's photos slide sideways (2026-11-20): a finger on the phone
  // or a trackpad moves the row, a thumbnail or a dot slides it to its
  // photo, and the thumbnail and dot of the photo in view are the marked
  // ones. The photos after the first are asked for once the page has
  // loaded, so a swipe never lands on an empty frame; another color's
  // photos, at once.
  function initGallery(gallery) {
    var slides = gallery.querySelector('.slides');
    if (!slides) return;
    var photos = slides.querySelectorAll('img');
    // The thumbnails, and on the phone the dots that take their place.
    var marks = [gallery.querySelectorAll('.thumbs button'), gallery.querySelectorAll('.dots button')];
    var current = 0;
    var aim = -1;
    var settle = 0;
    var frame = 0;
    function mark(index) {
      if (index === current || index < 0 || index >= photos.length) return;
      current = index;
      marks.forEach(function (group) {
        group.forEach(function (mark, i) {
          if (i === index) mark.setAttribute('aria-current', 'true');
          else mark.removeAttribute('aria-current');
        });
      });
    }
    function wake() {
      photos.forEach(function (photo) { if (photo.loading === 'lazy') photo.loading = 'eager'; });
    }
    if (document.readyState === 'complete') wake();
    else window.addEventListener('load', wake);
    marks.forEach(function (group) {
      group.forEach(function (button, i) {
        button.addEventListener('click', function () {
          wake();
          aim = i;
          clearTimeout(settle);
          settle = setTimeout(function () { aim = -1; }, 900);
          mark(i);
          var still = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
          slides.scrollTo({ left: i * slides.clientWidth, behavior: still ? 'auto' : 'smooth' });
        });
      });
    });
    slides.addEventListener('scroll', function () {
      if (frame) return;
      frame = requestAnimationFrame(function () {
        frame = 0;
        var index = Math.round(slides.scrollLeft / (slides.clientWidth || 1));
        // A thumbnail's slide passes the photos between: the mark stays on
        // the one asked for until the row gets there.
        if (aim >= 0) {
          if (index === aim) aim = -1;
          return;
        }
        mark(index);
      });
    }, { passive: true });
  }
  document.querySelectorAll('.gallery').forEach(initGallery);
  // «Ver ficha técnica completa» opens the folded sheet it leads to
  // (20261120230000).
  document.addEventListener('click', function (event) {
    if (!(event.target.closest && event.target.closest('a[href="#ficha"]'))) return;
    var fold = document.querySelector('#ficha details.pd-fold-sheet');
    if (fold) fold.open = true;
  });

  // ---- a model's sizes and colors (2026-11-21) ----------------------------
  // Each value of the selector is a link to its own page: Google and a page
  // without JavaScript follow it. Here a choice changes the page where it
  // is: the product part of the other variants is asked for ahead
  // (`x-vinabike-part: product`, a few KB instead of the whole page) and a
  // tap swaps it in without a reload, keeping the scroll and, for another
  // size of the same color, the photos in sight. The owner, that day: «es
  // como lento… hace un refresh medio raro» (each choice reloaded the page:
  // 1.2 to 1.4 s to its first byte, measured on the 3DF).
  var opts = document.querySelector('[data-opts-sheet]');
  var optsLabel = '';
  if (opts) {
    var optsLabelEl = opts.querySelector('[data-opts-label]');
    optsLabel = optsLabelEl ? optsLabelEl.textContent : '';
    // A tap outside the layer closes it.
    opts.addEventListener('click', function (event) { if (event.target === opts) opts.close(); });
  }
  var turn = 0;

  function pathOf(href) {
    try {
      var url = new URL(href, location.href);
      return url.origin === location.origin ? url.pathname : null;
    } catch (e) { return null; }
  }
  function readPart(doc) {
    var main = doc.querySelector('main');
    var section = main && main.querySelector('[data-product-id]');
    if (!section || !section.querySelector('.buy')) return null;
    var canonical = doc.querySelector('link[rel=canonical]');
    return { title: doc.title, canonical: canonical ? canonical.getAttribute('href') : '', main: main, question: doc.querySelector('[data-question]') };
  }
  // One request per variant and visit, shared by whoever asks first; a
  // failed one is asked again next time.
  function partOf(path) {
    if (!parts[path]) {
      parts[path] = fetch(path, { headers: { 'x-vinabike-part': 'product' }, credentials: 'same-origin' })
        .then(function (r) { return r.ok ? r.text() : null; })
        .then(function (text) { return text ? readPart(new DOMParser().parseFromString(text, 'text/html')) : null; })
        .catch(function () { return null; })
        .then(function (part) { if (!part) delete parts[path]; return part; });
    }
    return parts[path];
  }
  // The variants the selector under [root] leads to, asked for while the
  // visitor looks; not on a connection that saves data.
  function ahead(root) {
    var c = navigator.connection;
    if (c && (c.saveData || /(^|-)2g$/.test(c.effectiveType || ''))) return;
    [].forEach.call(root.querySelectorAll('.variant-picker a[href]'), function (a) {
      var path = pathOf(a.href);
      if (path) partOf(path);
    });
  }
  function idle(run) {
    if (window.requestIdleCallback) requestIdleCallback(run, { timeout: 2500 });
    else setTimeout(run, 800);
  }
  // The choice shows at once, before its part arrives.
  function markChoice(a) {
    var pick = a.closest('.pick');
    if (!pick) return;
    [].forEach.call(pick.querySelectorAll('.on'), function (el) { el.classList.remove('on'); });
    a.classList.remove('off');
    a.classList.add('on');
    var head = pick.querySelector('.pick-head strong');
    if (head) head.textContent = a.getAttribute('title') || head.textContent;
  }
  // Which value of which axis a choice is, to find it in the new selector.
  function keyOf(a) {
    var pick = a.closest('.pick'), picker = a.closest('.variant-picker');
    return { axis: picker ? [].indexOf.call(picker.querySelectorAll('.pick'), pick) : -1, title: a.getAttribute('title') };
  }
  function focusChoice(picker, key) {
    if (!picker || !key || key.axis < 0) return;
    var pick = picker.querySelectorAll('.pick')[key.axis];
    var found = pick && [].filter.call(pick.querySelectorAll('[title]'), function (el) { return el.getAttribute('title') === key.title; })[0];
    if (!found) return;
    if (!found.hasAttribute('href')) found.setAttribute('tabindex', '-1');
    found.focus({ preventScroll: true });
  }
  function copyAttributes(from, to) {
    [].slice.call(to.attributes).forEach(function (attr) { if (!from.hasAttribute(attr.name)) to.removeAttribute(attr.name); });
    [].forEach.call(from.attributes, function (attr) { to.setAttribute(attr.name, attr.value); });
  }
  // The photos in sight stay; their words name the variant now shown.
  function relabelGallery(gallery, next) {
    var now = next.querySelectorAll('.slides img');
    [].forEach.call(gallery.querySelectorAll('.slides img'), function (img, i) {
      if (now[i]) img.setAttribute('alt', now[i].getAttribute('alt') || '');
    });
    var slides = gallery.querySelector('.slides'), named = next.querySelector('.slides');
    if (slides && named && named.hasAttribute('aria-label')) slides.setAttribute('aria-label', named.getAttribute('aria-label'));
  }
  // The question sheet names the product asked about: its data and its
  // product line follow the choice (its script reads them when it opens).
  function swapQuestion(next) {
    var sheet = document.querySelector('[data-question]');
    if (!sheet || !next) return;
    [].forEach.call(next.attributes, function (attr) {
      if (attr.name.indexOf('data-') === 0) sheet.setAttribute(attr.name, attr.value);
    });
    ['.qs-product', '.qs-sugs'].forEach(function (selector) {
      var mine = sheet.querySelector(selector), theirs = next.querySelector(selector);
      if (mine && theirs) mine.parentNode.replaceChild(document.importNode(theirs, true), mine);
    });
  }
  function inView(el) {
    if (!el) return false;
    var r = el.getBoundingClientRect();
    return r.bottom > 0 && r.top < (window.innerHeight || 0);
  }

  // ---- the pictures through a choice (2026-11-22) ---------------------------
  // A part brings its own <img>s, and a new element starts empty even when
  // its picture is on the page already: the small ones are lazy, and each one
  // is decoded again. The swatches, the thumbnails and the photo blinked at
  // every choice (the owner: «hace como un flicker medio raro … las imágenes
  // chicas»). Now a picture already drawn keeps its element, and a new one in
  // sight is decoded before it takes its place.
  function imgKey(img) {
    return [img.getAttribute('src'), img.getAttribute('srcset'), img.getAttribute('sizes')].join(' ');
  }
  // The drawn pictures under [roots], by what they show.
  function drawnImages(roots) {
    var drawn = {};
    roots.forEach(function (root) {
      if (!root || !root.querySelectorAll) return;
      [].forEach.call(root.querySelectorAll('img'), function (img) {
        if (!img.complete || !img.naturalWidth) return;
        var key = imgKey(img);
        (drawn[key] = drawn[key] || []).push(img);
      });
    });
    return drawn;
  }
  // Each picture under [roots] that one of [drawn] already shows becomes that
  // element, with the new one's attributes (its words, its place).
  function keepImages(drawn, roots) {
    roots.forEach(function (root) {
      if (!root || !root.querySelectorAll) return;
      [].forEach.call(root.querySelectorAll('img'), function (img) {
        var same = drawn[imgKey(img)];
        var old = same && same.shift();
        if (!old) return;
        [].slice.call(old.attributes).forEach(function (attr) {
          if (!img.hasAttribute(attr.name)) old.removeAttribute(attr.name);
        });
        [].forEach.call(img.attributes, function (attr) {
          if (old.getAttribute(attr.name) !== attr.value) old.setAttribute(attr.name, attr.value);
        });
        img.parentNode.replaceChild(old, img);
      });
    });
  }
  // [imgs] load now: they are about to be seen.
  function eager(imgs) {
    [].forEach.call(imgs, function (img) {
      if (img.getAttribute('loading') === 'lazy') img.removeAttribute('loading');
    });
  }
  // The tree of [part], ready to swap in: the pictures it shows first (the
  // photo, the swatches, the thumbnails when they are in sight) that the page
  // does not show yet are decoded before, for a moment and a half at most;
  // the ones the page shows stay their elements (keepImages, in the swap).
  function ready(part) {
    var next = document.importNode(part.main, true);
    var section = productEl();
    var nextSection = next.querySelector('[data-product-id]');
    if (!section || !nextSection) return Promise.resolve(next);
    var drawn = drawnImages([section]);
    var thumbs = section.querySelector('.thumbs');
    var first = '#foto, .variant-picker img' + (thumbs && thumbs.offsetParent ? ', .thumbs img' : '');
    var waits = [];
    [].forEach.call(nextSection.querySelectorAll(first), function (img) {
      var same = drawn[imgKey(img)];
      if (same && same.shift()) return;
      eager([img]);
      if (img.decode) waits.push(img.decode().catch(function () { /* drawn when it comes */ }));
    });
    if (!waits.length) return Promise.resolve(next);
    return Promise.race([
      Promise.all(waits),
      new Promise(function (done) { setTimeout(done, 1500); })
    ]).then(function () { return next; });
  }
  // A choice about to be made (a pointer or a finger on it): its photo is
  // asked for ahead, as its page is.
  var warmed = {};
  function warm(part) {
    var photo = part && part.main.querySelector('[data-product-id] #foto');
    if (!photo || warmed[imgKey(photo)]) return;
    warmed[imgKey(photo)] = true;
    var img = new Image();
    if (photo.getAttribute('sizes')) img.sizes = photo.getAttribute('sizes');
    if (photo.getAttribute('srcset')) img.srcset = photo.getAttribute('srcset');
    img.src = photo.getAttribute('src');
  }

  // Puts [part], the page of the variant at [path], in place of the one in
  // sight: the section keeps its place (and the photos, when only the size
  // changes), its buy column and everything around it are the new page's,
  // [next] (`ready`), with the pictures already drawn kept as they are.
  function swap(part, next, path, link) {
    var main = document.getElementById('contenido');
    var section = productEl();
    var buy = section && section.querySelector('.buy');
    var nextSection = next.querySelector('[data-product-id]');
    var nextBuy = nextSection && nextSection.querySelector('.buy');
    var pdp = section && section.parentNode;
    var nextPdp = nextSection && nextSection.parentNode;
    if (!main || !buy || !nextBuy || !pdp || pdp.parentNode !== main || !nextPdp || nextPdp.parentNode !== next) {
      location.assign(path);
      return;
    }
    var inSheet = !!(opts && opts.contains(link));
    var active = document.activeElement;
    var refocus = active && (buy.contains(active) || (inSheet && opts.contains(active))) ? keyOf(link) : null;
    // What stays where it is on screen: the selector when it is in sight,
    // otherwise, below the buy part, what is being read.
    var anchor = buy.querySelector('.variant-picker');
    var anchorTop = inView(anchor) ? anchor.getBoundingClientRect().top : null;
    var pdpBottom = pdp.getBoundingClientRect().bottom;
    var fold = main.querySelector('#ficha details.pd-fold-sheet');
    var foldOpen = !!(fold && fold.open);
    var root = document.documentElement;
    root.style.overflowAnchor = 'none';

    // The section's own data: the product, its name, price and cart limit.
    copyAttributes(nextSection, section);
    // What leaves (and its pictures, which the new parts keep) and what comes.
    var around = [].slice.call(main.childNodes).filter(function (node) { return node !== pdp; });
    var leaving = [buy].concat(around);
    var coming = [nextBuy].concat([].slice.call(next.childNodes).filter(function (node) { return node !== nextPdp; }));
    var gallery = section.querySelector('.gallery'), nextGallery = nextSection.querySelector('.gallery');
    var newGallery = null;
    if (gallery && nextGallery) {
      var look = gallery.getAttribute('data-look');
      if (look !== null && look === nextGallery.getAttribute('data-look') &&
          gallery.querySelectorAll('.slide').length === nextGallery.querySelectorAll('.slide').length) {
        relabelGallery(gallery, nextGallery);
      } else {
        newGallery = nextGallery;
        leaving.push(gallery);
        coming.push(nextGallery);
      }
    }
    keepImages(drawnImages(leaving), coming);
    if (newGallery) {
      gallery.parentNode.replaceChild(newGallery, gallery);
      initGallery(newGallery);
    }
    buy.parentNode.replaceChild(nextBuy, buy);
    // The trail, what fits, the sheet and the related ones, around it.
    around.forEach(function (node) { main.removeChild(node); });
    var before = true;
    [].slice.call(next.childNodes).forEach(function (node) {
      if (node === nextPdp) { before = false; return; }
      if (before) main.insertBefore(node, pdp); else main.appendChild(node);
    });
    if (foldOpen) {
      var nextFold = main.querySelector('#ficha details.pd-fold-sheet');
      if (nextFold) nextFold.open = true;
    }

    document.title = part.title;
    var canonical = document.querySelector('link[rel=canonical]');
    if (canonical && part.canonical) canonical.setAttribute('href', part.canonical);
    try { history.replaceState(history.state, '', path + location.search + location.hash); } catch (e) { /* the address stays */ }
    swapQuestion(part.question);

    var nextAnchor = section.querySelector('.buy .variant-picker');
    var shift = anchorTop !== null && nextAnchor
      ? nextAnchor.getBoundingClientRect().top - anchorTop
      : pdpBottom < 0 ? pdp.getBoundingClientRect().bottom - pdpBottom : 0;
    if (Math.abs(shift) > 1) window.scrollBy(0, shift);
    requestAnimationFrame(function () { root.style.overflowAnchor = ''; });

    bindCartForms();
    watchBar();
    showInCart();
    initTrail();
    measureLists(main);
    viewProduct();
    if (opts && opts.open) fillOptions();
    if (refocus) focusChoice(inSheet ? opts.querySelector('.variant-picker') : nextAnchor, refocus);
    idle(function () { ahead(section); });
  }

  function choose(a, path) {
    var mine = ++turn;
    var section = productEl();
    var inSheet = !!(opts && opts.contains(a));
    markChoice(a);
    // Only a slow answer shows its wait.
    var slow = setTimeout(function () {
      if (mine !== turn) return;
      if (section) section.setAttribute('aria-busy', 'true');
      if (inSheet) opts.setAttribute('aria-busy', 'true');
    }, 150);
    partOf(path).then(function (part) {
      if (!part || mine !== turn) return { part: part };
      return ready(part).then(function (next) { return { part: part, next: next }; });
    }).catch(function () { return { part: null }; }).then(function (got) {
      clearTimeout(slow);
      if (mine !== turn) return;
      if (section) section.removeAttribute('aria-busy');
      if (opts) opts.removeAttribute('aria-busy');
      // Without its part the link does what it always did.
      if (got.part && got.next) swap(got.part, got.next, path, a);
      else location.assign(a.href);
    });
  }

  // The layer shows the page's own selector, photo, price and stock line.
  function fillOptions() {
    var product = productEl();
    var buy = product && product.querySelector('.buy');
    var picker = buy && buy.querySelector('.variant-picker');
    var slot = opts.querySelector('[data-opts-picker]');
    if (slot) {
      // The layer's swatches are the ones it showed (or copies of the
      // page's, which load at once): none blinks when it fills again.
      var copy = picker ? picker.cloneNode(true) : null;
      if (copy) {
        keepImages(drawnImages([slot]), [copy]);
        eager(copy.querySelectorAll('img'));
      }
      slot.textContent = '';
      if (copy) slot.appendChild(copy);
    }
    var shot = opts.querySelector('[data-opts-shot]');
    var photo = product && product.querySelector('#foto');
    if (shot && photo) shot.src = photo.currentSrc || photo.src;
    var name = opts.querySelector('[data-opts-name]');
    if (name && product) name.textContent = product.dataset.itemName || '';
    var price = opts.querySelector('[data-opts-price]'), shown = buy && buy.querySelector('.price');
    if (price && shown) price.textContent = shown.textContent;
    var can = !!(buy && buy.querySelector('form.cart'));
    var stock = opts.querySelector('[data-opts-stock]'), line = buy && buy.querySelector('.avail p');
    if (stock) {
      stock.textContent = '';
      if (line) stock.appendChild(line.cloneNode(true));
      var qty = document.querySelector('form.cart input[name=cantidad]');
      var n = Math.max(1, Math.floor(Number(qty ? qty.value : 1) || 1));
      if (can && n > 1) {
        var many = document.createElement('p');
        many.textContent = 'Cantidad: ' + n;
        stock.appendChild(many);
      }
    }
    var add = opts.querySelector('[data-opts-add]'), label = opts.querySelector('[data-opts-label]');
    if (add) { add.disabled = !can; add.classList.remove('is-done'); }
    if (label) label.textContent = can ? optsLabel : 'No disponible en esta combinación';
    var note = opts.querySelector('[data-opts-note]');
    if (note) note.hidden = true;
  }
  function openOptions() {
    fillOptions();
    opts.showModal();
  }
  // The layer's own button adds what it shows, says so and closes.
  document.addEventListener('click', function (event) {
    var button = event.target.closest && event.target.closest('[data-opts-add]');
    // Disabled says «not this one»; a click on its way only waits.
    if (!button || button.disabled || button.vbBusy || !opts) return;
    button.vbBusy = true;
    addCurrent(null).then(function (added) {
      var label = opts.querySelector('[data-opts-label]'), note = opts.querySelector('[data-opts-note]');
      if (added > 0) {
        button.classList.add('is-done');
        if (label) label.textContent = 'Agregado al carrito';
        setTimeout(function () {
          button.vbBusy = false;
          if (opts.open) opts.close();
          fillOptions();
        }, 900);
        return;
      }
      button.vbBusy = false;
      if (note) {
        note.hidden = false;
        note.textContent = added === 0
          ? 'Ya tienes en el carrito todo el stock disponible.'
          : 'No pudimos guardar tu carrito en este navegador. Escríbenos por WhatsApp y te ayudamos.';
      }
    });
  });

  if (switching) {
    if (document.readyState === 'complete') idle(function () { ahead(document); });
    else window.addEventListener('load', function () { idle(function () { ahead(document); }); });
    // A finger or a pointer on a choice asks for it, and for its photo,
    // before the tap.
    ['pointerover', 'touchstart', 'focusin'].forEach(function (type) {
      document.addEventListener(type, function (event) {
        var a = event.target.closest && event.target.closest('.variant-picker a[href]');
        var path = a && pathOf(a.href);
        if (path) partOf(path).then(warm);
      }, { passive: true });
    });
    document.addEventListener('click', function (event) {
      var a = event.target.closest && event.target.closest('.variant-picker a[href]');
      if (!a || event.defaultPrevented || event.button || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      var path = pathOf(a.href);
      if (!path) return;
      event.preventDefault();
      choose(a, path);
    });
  }

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
    closeLevels();
    if (opts && opts.open) opts.close();
  }

  // The phone menu's levels: a row with children opens its level over the
  // drawer and gives the focus to its «‹», which closes it and gives the
  // focus back to the row; the search closes the menu, and the menu always
  // opens at its first level. Without scripts the links' targets do it.
  var menuSheet = document.querySelector('.menu-sheet');
  function closeLevels() {
    if (!menuSheet) return;
    menuSheet.querySelectorAll('.pm-level.on').forEach(function (level) { level.classList.remove('on'); });
  }
  if (menuSheet) {
    menuSheet.addEventListener('click', function (event) {
      var open = event.target.closest('[data-pm-open]');
      if (open) {
        event.preventDefault();
        var level = document.getElementById(open.dataset.pmOpen);
        if (!level) return;
        level.classList.add('on');
        var first = level.querySelector('[data-pm-back]');
        if (first) first.focus({ preventScroll: true });
        return;
      }
      var back = event.target.closest('[data-pm-back]');
      if (back) {
        event.preventDefault();
        var shown = back.closest('.pm-level');
        shown.classList.remove('on');
        var row = menuSheet.querySelector('[data-pm-open="' + shown.id + '"]');
        if (row) row.focus({ preventScroll: true });
        return;
      }
      if (event.target.closest('[data-search-open]')) closeSheets();
    });
    var menuBox = document.getElementById('menu-toggle');
    if (menuBox) menuBox.addEventListener('change', function () { if (!menuBox.checked) closeLevels(); });
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
    // A product page's question names the product asked about.
    if (method) track('contact', link.dataset.itemId ? { method: method, item_id: link.dataset.itemId, item_name: link.dataset.itemName || '' } : { method: method });
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

  // ---- the customer's session (Flutter's, `sb-<ref>-auth-token`) --------
  // Read as gotrue-dart writes it; an expired one is renewed under the lock
  // supabase_flutter takes and written back in the same format.
  var sbUrl = (body.dataset.sbUrl || '').replace(/\/+$/, ''), sbKey = body.dataset.sbKey || '';
  var sbRef = '';
  try { sbRef = new URL(sbUrl).host.split('.')[0]; } catch (e) { /* no session */ }
  var authKey = 'sb-' + sbRef + '-auth-token';
  var profileKey = 'vinabike.account-profile.v1.' + tenant;
  function readSession() {
    try {
      var s = JSON.parse(localStorage.getItem(authKey) || 'null');
      return s && s.access_token && s.user && s.user.id ? s : null;
    } catch (e) { return null; }
  }
  function jwtExp(token) {
    try { return JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).exp || 0; } catch (e) { return 0; }
  }
  function authCall(path, payload, token) {
    return fetch(sbUrl + path, {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + (token || sbKey), 'content-type': 'application/json' },
      body: JSON.stringify(payload || {})
    }).then(function (r) { return r.ok ? r.text().then(function (t) { return t ? JSON.parse(t) : null; }) : null; });
  }
  var sessionPromise = null;
  // [force]: Supabase refused the token before it expired (revoked, or the
  // clock is off): renew it anyway.
  function currentSession(force) {
    if (sessionPromise && !force) return sessionPromise;
    var stale = force ? (readSession() || {}).access_token : null;
    sessionPromise = new Promise(function (resolve) {
      var s = readSession();
      if (!s || !sbUrl) { resolve(null); return; }
      if (!force && jwtExp(s.access_token) * 1000 - Date.now() > 60e3) { resolve(s); return; }
      if (!s.refresh_token) { resolve(null); return; }
      var renew = function () {
        // Another tab may have renewed it already.
        var latest = readSession();
        if (latest && latest.access_token !== stale && jwtExp(latest.access_token) * 1000 - Date.now() > 60e3) return Promise.resolve(latest);
        return authCall('/auth/v1/token?grant_type=refresh_token', { refresh_token: (latest || s).refresh_token }).then(function (r) {
          if (!r || !r.access_token || !r.user) return null;
          var next = {
            access_token: r.access_token, expires_in: r.expires_in, expires_at: r.expires_at || jwtExp(r.access_token),
            refresh_token: r.refresh_token, token_type: r.token_type || 'bearer',
            provider_token: s.provider_token || null, provider_refresh_token: s.provider_refresh_token || null, user: r.user
          };
          try { localStorage.setItem(authKey, JSON.stringify(next)); } catch (e) { /* this page still uses it */ }
          return next;
        });
      };
      var run = navigator.locks && navigator.locks.request ? navigator.locks.request('lock:' + authKey, renew) : renew();
      run.then(resolve, function () { resolve(null); });
    });
    return sessionPromise;
  }
  // The store's customer behind the session (`customers`, by tenant), as
  // `CustomerAccountService.isAuthenticated` requires it.
  function customerProfile() {
    return currentSession().then(function (s) {
      if (!s) return null;
      // greeting_name: the greeting the customer chose, computed by the base
      // (20261121200000) so the rule is not repeated here.
      return fetch(sbUrl + '/rest/v1/customers?select=id,name,email,auth_user_id,tenant_id,greeting_name&auth_user_id=eq.' +
        encodeURIComponent(s.user.id) + '&tenant_id=eq.' + encodeURIComponent(tenant) + '&limit=1', {
        headers: { apikey: sbKey, authorization: 'Bearer ' + s.access_token, accept: 'application/json' }
      }).then(function (r) { return r.ok ? r.json() : null; }).then(function (rows) {
        var row = rows && rows[0];
        return row && row.auth_user_id === s.user.id && row.tenant_id === tenant ? { session: s, row: row } : null;
      });
    });
  }
  // supabase_flutter's signOut (scope local): end this session, forget it.
  function signOut() {
    return currentSession().then(function (s) {
      if (!s) return null;
      return fetch(sbUrl + '/auth/v1/logout?scope=local', {
        method: 'POST', headers: { apikey: sbKey, authorization: 'Bearer ' + s.access_token }
      }).catch(function () { return null; });
    }).then(function () {
      try { localStorage.removeItem(authKey); } catch (e) { /* nothing kept */ }
      try { sessionStorage.removeItem(profileKey); } catch (e) { /* nothing kept */ }
      sessionPromise = null;
    });
  }
  window.vinabikeSession = {
    key: authKey, read: readSession, current: function () { return currentSession(false); },
    renew: function () { return currentSession(true); }, profile: customerProfile, signOut: signOut
  };

  // ---- the header's account (CustomerAccountMenu) -------------------------
  // customerFirstName: «Usuario», «Cliente» or the email's name are filler.
  function firstName(row) {
    var name = String(row.name || '').trim();
    if (!name) return null;
    var lower = name.toLowerCase();
    if (lower === 'usuario' || lower === 'cliente') return null;
    var email = String(row.email || '').trim().toLowerCase(), at = email.indexOf('@');
    if (at > 0 && lower === email.slice(0, at)) return null;
    var greeting = String(row.greeting_name || '').trim();
    return greeting || name.split(/\s+/)[0];
  }
  var header = document.querySelector('header.top');
  // A breadcrumb wider than the screen shows its end (the most precise
  // category) and fades on the side that has more.
  // Another size or color brings its own trail: it starts the same way.
  var trailFade = null;
  function initTrail() {
    var trail = document.querySelector('.crumbs ol');
    trailFade = null;
    if (!trail) return;
    var fade = function () {
      var more = trail.scrollWidth - trail.clientWidth;
      trail.classList.toggle('more-l', more > 1 && trail.scrollLeft > 1);
      trail.classList.toggle('more-r', more > 1 && trail.scrollLeft < more - 1);
    };
    trail.scrollLeft = trail.scrollWidth;
    trail.addEventListener('scroll', fade, { passive: true });
    trailFade = fade;
    fade();
  }
  initTrail();
  window.addEventListener('resize', function () { if (trailFade) trailFade(); });
  // The product page's photo stays under the sticky header (`--top-h`),
  // whatever the header holds (a top banner makes it taller).
  if (header && window.ResizeObserver) new ResizeObserver(function () {
    document.documentElement.style.setProperty('--top-h', header.offsetHeight + 'px');
  }).observe(header);
  function paintAccount(seen) {
    if (!header) return;
    var box = header.querySelector('[data-acct]');
    if (!box) return;
    header.querySelector('[data-acct-initial]').textContent = seen ? seen.initial : '';
    header.querySelector('[data-acct-name]').textContent = (seen && seen.first) || 'Mi cuenta';
    header.querySelector('[data-acct-sub]').hidden = !(seen && seen.first);
    box.hidden = !seen;
    header.querySelectorAll('.login,.sheet-login').forEach(function (e) { e.hidden = !!seen; });
    header.querySelectorAll('.sheet-account').forEach(function (e) { e.hidden = !seen; });
  }
  if (readSession()) {
    customerProfile().then(function (found) {
      if (!found) {
        try { sessionStorage.removeItem(profileKey); } catch (e) { /* nothing kept */ }
        paintAccount(null);
        return;
      }
      var first = firstName(found.row), email = String(found.row.email || '').trim();
      var source = first || email;
      var seen = { uid: found.session.user.id, first: first, initial: source ? Array.from(source)[0].toUpperCase() : '·' };
      try { sessionStorage.setItem(profileKey, JSON.stringify(seen)); } catch (e) { /* drawn anyway */ }
      paintAccount(seen);
    }, function () { /* keep what the first paint showed */ });
  } else if (window.vinabikeAccountSeen) {
    paintAccount(null);
  }
  var accountMenu = header && header.querySelector('.acct-menu');
  var accountButton = header && header.querySelector('.acct-btn');
  function openMenu(open) {
    if (!accountMenu) return;
    accountMenu.hidden = !open;
    accountButton.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open) { var first = accountMenu.querySelector('.acct-item'); if (first) first.focus(); }
  }
  if (accountButton) {
    accountButton.addEventListener('click', function () { openMenu(accountMenu.hidden); });
    document.addEventListener('click', function (event) {
      if (!accountMenu.hidden && !event.target.closest('[data-acct]')) openMenu(false);
    });
    accountMenu.addEventListener('keydown', function (event) {
      var items = Array.prototype.slice.call(accountMenu.querySelectorAll('.acct-item'));
      var at = items.indexOf(document.activeElement);
      if (event.key === 'Escape') { openMenu(false); accountButton.focus(); }
      else if (event.key === 'ArrowDown') { event.preventDefault(); items[(at + 1) % items.length].focus(); }
      else if (event.key === 'ArrowUp') { event.preventDefault(); items[(at - 1 + items.length) % items.length].focus(); }
    });
  }
  document.addEventListener('click', function (event) {
    var out = event.target.closest && event.target.closest('[data-act=sign-out]');
    if (!out || !header || !header.contains(out)) return;
    out.disabled = true;
    // PublicStoreLayout.signOutCustomer: then to the home.
    signOut().then(function () { location.assign('/'); });
  });

  paintBadge();
  window.addEventListener('storage', function (event) { if (event.key === cartKey) paintBadge(); });
  window.addEventListener('pageshow', paintBadge);
})();
''';
