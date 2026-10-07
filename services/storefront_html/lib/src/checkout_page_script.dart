/// The checkout's script, after the page script that owns the cart
/// (`window.vinabikeCart`). It is Flutter's `CheckoutPage` in the browser,
/// with the same public calls and the same records, so the two stores can
/// hand an order to each other:
///
/// The records themselves (snapshot, access, cart outcome) are
/// `checkoutRecordsScript`, loaded before this one.
///
/// - **Recovery.** Before the order is sent, the exact payload is saved in
///   sessionStorage as `CheckoutSessionStore` does
///   (`vinabike.public-checkout.v1.<tenant>`, schema 1, two hours), with the
///   cart's revision. A retry resends that payload and never rebuilds it;
///   the receipt is attached to it, and the order's access is kept apart
///   (`vinabike.public-order-access.v1.<b64 tenant>.<b64 order>`). Flutter's
///   order page reads both.
/// - **Order.** `create_public_online_order_with_access` with the visitor's
///   session when there is one (the database checks `customer_id` against
///   it), Mercado Pago's preference through `mercadopago-create-preference`,
///   and for a transfer the cart loses what was ordered once
///   (`consumeCartOnce`, its outcome under
///   `vinabike.public-cart-preserved.v1.…`) before the order page opens.
/// - **Session.** The Flutter store's own (`sb-<ref>-auth-token` in
///   localStorage), through the page script's `window.vinabikeSession`,
///   which renews an expired one and writes it back as gotrue-dart reads it.
const checkoutPageScript = r'''
(function (root) {
  var cart = window.vinabikeCart;
  if (!root || !cart || !window.vinabikeCheckoutRecords) return;
  var D = root.dataset;
  var tenant = D.tenant, sbUrl = D.sbUrl.replace(/\/+$/, ''), sbKey = D.sbKey;
  var checkoutKey = 'vinabike.public-checkout.v1.' + tenant;
  var EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
  function $(s) { return root.querySelector(s); }
  function $$(s) { return Array.prototype.slice.call(root.querySelectorAll(s)); }
  var form = $('[data-co-form]');
  var payButton = $('[data-act=place]');


  var R = window.vinabikeCheckoutRecords(tenant, cart);
  var uuid = R.uuid, ssRead = R.ssRead, ssClear = R.ssClear, parseReceipt = R.parseReceipt,
    parseSnapshot = R.parseSnapshot, readSnapshot = R.readSnapshot, saveSnapshot = R.saveSnapshot,
    saveOrderAccess = R.saveOrderAccess, consumeCartOnce = R.consumeCartOnce;
  function money(n) { return '$ ' + Math.round(n).toLocaleString('es-CL'); }
  function nowIso() { return new Date().toISOString(); }
  function text(v) { return v == null ? '' : String(v).trim(); }
  var toastTimer = null;
  function toast(message, seconds) {
    var el = $('[data-co-toast]');
    el.textContent = message;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, (seconds || 4) * 1000);
  }

  // ---- Supabase ------------------------------------------------------------
  function call(path, body, token, timeoutMs) {
    var controller = window.AbortController ? new AbortController() : null;
    var timer = controller ? setTimeout(function () { controller.abort(); }, timeoutMs || 30000) : null;
    return fetch(sbUrl + path, {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + (token || sbKey), 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify(body),
      signal: controller ? controller.signal : undefined
    }).then(function (r) {
      clearTimeout(timer);
      return r.text().then(function (t) {
        var data = null;
        try { data = t ? JSON.parse(t) : null; } catch (e) { data = null; }
        if (!r.ok) { var err = new Error('http ' + r.status); err.status = r.status; err.data = data; throw err; }
        return data;
      });
    }, function (error) { clearTimeout(timer); throw error; });
  }
  function rpc(name, body, token) { return call('/rest/v1/rpc/' + name, body, token); }
  function select(table, query, token) {
    return fetch(sbUrl + '/rest/v1/' + table + '?' + query, {
      headers: { apikey: sbKey, authorization: 'Bearer ' + (token || sbKey), accept: 'application/json' }
    }).then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); });
  }

  // The customer's session: the page script owns it (`vinabikeSession`,
  // renewed under supabase_flutter's lock and written back as it reads it).
  function session() {
    return window.vinabikeSession ? window.vinabikeSession.current() : Promise.resolve(null);
  }

  // ---- state ---------------------------------------------------------------
  var state = {
    lines: null, snapshot: null, restored: false, storageDown: false,
    quote: null, quoteSig: null, quoteLoading: false, quoteError: null, quoteSeq: 0,
    processing: false, attempt: uuid(), creationAttempted: false,
    account: null, addresses: [], selected: null, resolved: null,
    places: false, placesToken: uuid(), outcomeMessage: null, recoveryMessage: null,
    accountTried: false, addressTried: false
  };

  function field(name) { return form.querySelector('[name="' + name + '"]'); }
  function value(name) { var el = field(name); return el ? el.value.trim() : ''; }
  function setValue(name, v) { var el = field(name); if (el) el.value = v == null ? '' : String(v); }
  function radio(group) { var el = form.querySelector('input[name="' + group + '"]:checked'); return el ? el.value : ''; }
  function delivery() { return radio('delivery') || 'shipping'; }
  function payment() { return radio('payment'); }
  function locked() { return state.processing || state.creationAttempted || !!(state.snapshot); }

  function show(view) {
    $('[data-co-full]').hidden = view !== 'full';
    $('[data-co-empty]').hidden = view !== 'empty';
    $('[data-co-loading]').hidden = view !== 'loading';
    $('[data-co-failed]').hidden = view !== 'failed';
    root.setAttribute('data-co-ready', view);
  }

  // ---- summary -------------------------------------------------------------
  function itemGross() {
    var l = state.lines;
    if (!l || !l.valid || typeof l.gross !== 'number' || l.gross !== Math.round(l.gross)) return null;
    return l.gross;
  }
  function signature() { var g = itemGross(); return g == null ? null : tenant + '|' + delivery() + '|' + g; }
  function hasQuote() {
    var q = state.quote, sig = signature();
    return !!(q && sig && sig === state.quoteSig && q.delivery_type === delivery() && q.item_gross === itemGross());
  }

  function paintSummary() {
    var snap = state.snapshot, l = state.lines;
    var rows = $('[data-co-rows]'), amounts = $('[data-co-amounts]');
    $('[data-co-frozen]').hidden = !state.restored;
    if (snap) {
      rows.innerHTML = snap.order_items.map(function (it) {
        var sku = text(it.product_sku);
        var esc = function (s) { var d = document.createElement('span'); d.textContent = s; return d.innerHTML; };
        return '<li class="co-row"><div class="co-row-shot">' + root.dataset.receiptIcon + '</div><div class="co-row-body">' +
          '<p class="co-row-name">' + esc(text(it.product_name) || 'Producto') + '</p><p class="co-row-q">' +
          esc((sku ? 'SKU: ' + sku + ' · ' : '') + 'Cantidad: ' + it.quantity) + '</p></div><p class="co-row-sub">' + money(it.subtotal) + '</p></li>';
      }).join('');
      var od = snap.order_data;
      amounts.innerHTML = '<p class="co-metric"><span>Subtotal neto</span><b>' + money(od.subtotal) + '</b></p>' +
        '<p class="co-metric sec"><span>IVA</span><b>' + money(od.tax_amount) + '</b></p>';
    } else if (l) {
      rows.innerHTML = l.rows;
      amounts.innerHTML = l.valid
        ? '<p class="co-metric"><span></span><b>' + money(l.net) + '</b></p><p class="co-metric sec"><span></span><b>' + money(l.tax) + '</b></p>'
        : '<p class="co-warn"></p><p class="co-metric"><span>Total productos</span><b>' + (l.knownGross == null ? '—' : money(l.knownGross)) + '</b></p>';
      if (l.valid) {
        var spans = amounts.querySelectorAll('span');
        spans[0].textContent = l.netLabel; spans[1].textContent = l.ivaLabel;
      } else {
        amounts.querySelector('.co-warn').textContent = l.block || 'No podemos validar los impuestos de este carrito.';
      }
    }
    var kind = snap ? snap.handoff.delivery_type : delivery();
    $('[data-co-ship-label]').textContent = kind === 'pickup' ? 'Retiro' : 'Envío';
    var shipValue = '—', totalValue = '—', note = null;
    if (snap) {
      var ship = snap.order_data.shipping_cost;
      shipValue = kind === 'pickup' || ship === 0 ? 'Sin costo' : money(ship);
      totalValue = money(snap.order_data.total);
    } else if (hasQuote()) {
      var q = state.quote;
      shipValue = q.delivery_type === 'pickup' ? 'Sin costo' : money(q.shipping_gross);
      totalValue = money(q.item_gross + q.shipping_gross);
      if (q.delivery_type !== 'pickup') note = 'IVA incluido · entrega estimada entre ' + q.estimated_min_business_days + ' y ' + q.estimated_max_business_days + ' días hábiles.';
    } else if (state.quoteLoading) {
      shipValue = 'Calculando…';
    }
    $('[data-co-ship-value]').textContent = shipValue;
    $('[data-co-total]').textContent = totalValue;
    var noteEl = $('[data-co-ship-note]');
    noteEl.hidden = !note; noteEl.textContent = note || '';
    $('[data-co-ship-wait]').hidden = !!snap || !state.quoteLoading;
    var err = $('[data-co-ship-err]');
    err.hidden = !!snap || !state.quoteError;
    $('[data-co-ship-err-text]').textContent = state.quoteError || '';
    err.querySelector('button').disabled = state.quoteLoading;
    var recovery = state.recoveryMessage || state.outcomeMessage;
    var box = $('[data-co-recovery]');
    box.hidden = !recovery; box.textContent = recovery || '';
    paintButton();
  }

  function paintButton() {
    var receipt = state.snapshot && state.snapshot.receipt;
    var label = receipt ? 'CONTINUAR CON PEDIDO' : (state.snapshot || state.creationAttempted) ? 'REINTENTAR CONFIRMACIÓN' : 'REALIZAR PEDIDO';
    var ready = locked() || (!state.quoteLoading && state.lines && state.lines.valid && hasQuote() && !!payment());
    payButton.disabled = state.processing || state.storageDown || !ready;
    payButton.classList.toggle('busy', state.processing);
    payButton.innerHTML = state.processing ? '<span class="co-spin" aria-label="Procesando"></span>' : '';
    if (!state.processing) { var s = document.createElement('span'); s.textContent = label; payButton.appendChild(s); }
    $('[data-co-back]').classList.toggle('off', state.processing || locked());
    form.classList.toggle('co-locked', locked());
    $$('[data-co-form] input, [data-co-form] textarea, [data-co-form] select').forEach(function (el) { el.disabled = locked(); });
  }

  // ---- lines ---------------------------------------------------------------
  var linesSeq = 0;
  function loadLines() {
    var saved;
    try { saved = cart.lines(); } catch (e) { show('failed'); return Promise.resolve(); }
    if (!saved.length) { state.lines = null; show('empty'); return Promise.resolve(); }
    var mine = ++linesSeq;
    var q = saved.map(function (l) { return l.id + ':' + l.q; }).join(',');
    return fetch(D.linesUrl + '?l=' + encodeURIComponent(q), { headers: { accept: 'application/json' }, cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error(String(r.status)); return r.json(); })
      .then(function (data) {
        if (mine !== linesSeq) return;
        if (data.adjusted > 0) {
          var limits = {};
          data.lines.forEach(function (l) { limits[l.id] = l.limit; });
          // Saved back as the cart page does (and Flutter on restore).
          cart.update(function (current) {
            return current.filter(function (l) { return data.gone.indexOf(l.id) < 0; }).map(function (l) {
              var limit = limits[l.id];
              return typeof limit === 'number' && l.q > limit ? { id: l.id, q: limit } : l;
            });
          }).then(cart.badge, function () {});
        }
        if (!data.lines.length) { state.lines = null; show('empty'); return; }
        state.lines = data;
        show('full');
        paintSummary();
        measureBegin(data);
        quote(false);
      })
      .catch(function () { if (mine === linesSeq) show('failed'); });
  }

  var begun = false, measured = null, steps = {};
  function measureBegin(data) {
    if (begun || !data.valid || data.gross == null) return;
    begun = true;
    var m = window.vinabikeMeasure;
    if (!m) return;
    var items = data.items.map(function (it) {
      return { id: text(it.product_sku) || text(it.product_id), name: it.product_name, price: it.unit_price, quantity: it.quantity };
    }).filter(function (it) { return it.id; });
    if (!items.length) return;
    measured = {
      value: data.gross,
      items: items.map(function (it) { return { item_id: it.id, item_name: it.name, price: it.price, quantity: it.quantity }; })
    };
    m.pixel('InitiateCheckout', {
      content_ids: items.map(function (it) { return it.id; }), content_type: 'product',
      contents: items.map(function (it) { return { id: it.id, quantity: it.quantity, item_price: it.price }; }),
      num_items: items.reduce(function (n, it) { return n + it.quantity; }, 0), value: data.gross, currency: 'CLP'
    });
    m.track('begin_checkout', {
      currency: 'CLP', value: data.gross,
      items: items.map(function (it) { return { item_id: it.id, item_name: it.name, price: it.price, quantity: it.quantity }; })
    });
  }

  // `add_shipping_info` once the customer says where it goes (picks pickup
  // or an address) and `add_payment_info` once they pick how to pay; each
  // once, and at «Confirmar» for the one left as it came.
  function measureStep(step) {
    var m = window.vinabikeMeasure;
    if (!m || !measured || steps[step]) return;
    steps[step] = true;
    var params = { currency: 'CLP', value: measured.value, items: measured.items };
    if (step === 'shipping') params.shipping_tier = delivery() === 'pickup' ? 'retiro' : 'despacho';
    else params.payment_type = payment();
    m.track(step === 'shipping' ? 'add_shipping_info' : 'add_payment_info', params);
  }

  // ---- shipping quote (quote_public_online_shipping) ---------------------
  function parseQuote(r) {
    if (!r || typeof r !== 'object') throw new Error('quote');
    function whole(k) { var v = typeof r[k] === 'number' ? r[k] : Number(r[k]); if (!isFinite(v) || v < 0 || Math.abs(v - Math.round(v)) > 1e-6) throw new Error(k); return Math.round(v); }
    var q = {
      delivery_type: String(r.delivery_type || ''), item_gross: whole('item_gross'), shipping_gross: whole('shipping_gross'),
      shipping_net: whole('shipping_net'), shipping_tax: whole('shipping_tax'), tax_rate: whole('tax_rate'),
      estimated_min_business_days: whole('estimated_min_business_days'), estimated_max_business_days: whole('estimated_max_business_days')
    };
    if (['shipping', 'pickup'].indexOf(q.delivery_type) < 0 || q.shipping_gross !== q.shipping_net + q.shipping_tax ||
        (q.delivery_type === 'pickup' && q.shipping_gross !== 0)) throw new Error('quote');
    return q;
  }
  function quote(force) {
    var gross = itemGross();
    if (gross == null) {
      state.quoteLoading = false;
      state.quoteError = state.lines && state.lines.valid ? 'El carrito contiene un monto que no puede expresarse en pesos completos.' : null;
      paintSummary();
      return Promise.resolve(null);
    }
    var kind = delivery(), sig = tenant + '|' + kind + '|' + gross;
    if (!force && state.quoteSig === sig && state.quote) return Promise.resolve(state.quote);
    var mine = ++state.quoteSeq;
    state.quoteLoading = true; state.quoteError = null;
    paintSummary();
    return rpc('quote_public_online_shipping', { p_tenant_id: tenant, p_delivery_type: kind, p_item_gross: gross, p_country_code: 'CL' })
      .then(function (r) {
        var q = parseQuote(r);
        if (q.delivery_type !== kind || q.item_gross !== gross) throw new Error('mismatch');
        if (mine !== state.quoteSeq || signature() !== sig) return null;
        state.quote = q; state.quoteSig = sig; state.quoteLoading = false; state.quoteError = null;
        paintSummary();
        return q;
      })
      .catch(function () {
        if (mine !== state.quoteSeq) return null;
        state.quote = null; state.quoteSig = null; state.quoteLoading = false;
        state.quoteError = 'No pudimos calcular el despacho. Reintenta antes de pagar.';
        paintSummary();
        return null;
      });
  }

  // ---- delivery and address ------------------------------------------------
  function paintDelivery() {
    var pickup = delivery() === 'pickup';
    $('[data-co-pickup]').hidden = !pickup;
    $('[data-co-shipping]').hidden = pickup;
    var signed = !!state.account;
    $('[data-co-saved]').hidden = pickup || !signed || !state.addresses.length;
    $('[data-co-search]').hidden = !state.places;
    $('[data-co-manual]').hidden = state.places || state.placesUnknown;
    $('[data-co-label]').hidden = !signed || !!state.selected;
    $('[data-co-manage]').hidden = !signed || !state.selected;
    var accountBox = $('[data-co-account]');
    accountBox.hidden = signed;
  }

  function addressDisplay(a) {
    var line = [a.street, a.number].filter(function (p) { return p && p.trim(); }).join(' ').trim();
    var c = (a.comuna || '').trim(), city = (a.city || '').trim(), region = (a.region || '').trim();
    var parts = [];
    if (line) parts.push(line);
    if (a.apartment && a.apartment.trim()) parts.push(a.apartment.trim());
    if (c) parts.push(c);
    if (city && city.toLowerCase() !== c.toLowerCase()) parts.push(city);
    if (region && region.toLowerCase() !== city.toLowerCase()) parts.push(region);
    if (a.chile !== false) parts.push('Chile');
    return parts.join(', ');
  }
  function normalizedCity(city, comuna, region) {
    city = (city || '').trim(); comuna = (comuna || '').trim(); region = (region || '').trim();
    if (!comuna) return city;
    if (!city) return comuna;
    if (city.toLowerCase() === region.toLowerCase()) return comuna;
    return city;
  }
  function fillAddress(r) {
    setValue('street', r.street); setValue('street_number', r.number || ''); setValue('apartment', r.apartment || '');
    setValue('comuna', r.comuna); setValue('city', normalizedCity(r.city, r.comuna, r.region));
    setValue('region', r.region); setValue('postal_code', r.postal || '');
  }
  function applySaved(addr) {
    var r = { street: addr.street_address || '', number: addr.street_number, apartment: addr.apartment, comuna: addr.comuna || '', city: addr.city || '', region: addr.region || '', postal: addr.postal_code };
    state.selected = addr;
    state.resolved = r;
    setValue('address', addressDisplay(r));
    setValue('address_label', addr.label || '');
    field('save_address').checked = false;
    fillAddress(r);
    if (!value('name')) setValue('name', addr.recipient_name || '');
    if (!value('phone')) setValue('phone', addr.phone || '');
    field('saved').value = addr.id;
    paintDelivery();
    measureStep('shipping');
  }
  // _shippingAddressForOrder
  function orderAddress() {
    var search = value('address'), street = value('street'), number = value('street_number'), apt = value('apartment');
    var comuna = value('comuna'), city = value('city'), region = value('region'), postal = value('postal_code');
    return {
      formatted: search || addressDisplay({ street: street, number: number, apartment: apt, comuna: comuna, city: city, region: region }),
      street: street || search, number: number || null, apartment: apt || null,
      comuna: comuna || city, city: city || comuna, region: region, postal: postal || null,
      lat: state.resolved && state.resolved.lat, lng: state.resolved && state.resolved.lng
    };
  }

  // Google Places through google-places-proxy, one session token per pick.
  var sugTimer = null, sugSeq = 0, sugItems = [], sugIndex = -1;
  var sugList = $('[data-co-sugs]');
  function closeSugs() { sugList.hidden = true; sugItems = []; sugIndex = -1; field('address').setAttribute('aria-expanded', 'false'); }
  function paintSugs(items, note) {
    sugItems = items; sugIndex = -1;
    sugList.innerHTML = '';
    if (note) {
      var li = document.createElement('li'); li.className = 'co-sugs-note'; li.innerHTML = note; sugList.appendChild(li);
    }
    items.forEach(function (s, i) {
      var li = document.createElement('li');
      li.setAttribute('role', 'option'); li.id = 'co-sug-' + i; li.dataset.index = String(i);
      li.innerHTML = root.dataset.placeIcon;
      var span = document.createElement('span'); span.textContent = s.description; li.appendChild(span);
      sugList.appendChild(li);
    });
    sugList.hidden = false;
    field('address').setAttribute('aria-expanded', 'true');
  }
  function suggest() {
    var q = value('address');
    clearTimeout(sugTimer);
    if (!state.places || q.length < 3) { closeSugs(); return; }
    sugTimer = setTimeout(function () {
      var mine = ++sugSeq;
      paintSugs([], '<span class="co-spin" style="width:18px;height:18px;color:var(--k-prim)"></span>');
      call('/functions/v1/google-places-proxy', { action: 'autocomplete', input: q, sessionToken: state.placesToken, tenantId: tenant })
        .then(function (r) {
          if (mine !== sugSeq) return;
          var list = r && r.status === 'OK' && Array.isArray(r.predictions) ? r.predictions.map(function (p) { return { placeId: p.place_id, description: p.description }; }) : [];
          if (list.length) paintSugs(list); else paintSugs([], 'No encontramos coincidencias');
        }, function () { if (mine === sugSeq) paintSugs([], 'No encontramos coincidencias'); });
    }, 300);
  }
  function pickSuggestion(s) {
    closeSugs();
    field('address').blur();
    call('/functions/v1/google-places-proxy', { action: 'details', placeId: s.placeId, sessionToken: state.placesToken, tenantId: tenant })
      .then(function (r) {
        if (!r || r.status !== 'OK' || !r.result) return;
        // One reading of a place for the checkout and the portal (places_script).
        var resolved = window.vinabikePlaces.resolve(r.result);
        state.selected = null;
        state.resolved = resolved;
        setValue('address', s.description.trim() || addressDisplay(resolved));
        var labelValue = value('address_label');
        if (!labelValue || labelValue === 'Dirección de entrega') {
          setValue('address_label', 'Dirección ' + (resolved.comuna || resolved.city || 'Entrega'));
        }
        field('save_address').checked = !!state.account;
        fillAddress(resolved);
        state.placesToken = uuid();
        paintDelivery();
        measureStep('shipping');
      }, function () {});
  }

  // ---- account -------------------------------------------------------------
  function loadAccount() {
    return session().then(function (s) {
      if (!s) return;
      return rpc('provision_current_public_store_customer', { p_tenant_id: tenant }, s.access_token).then(function () {
        return select('customers', 'select=*&auth_user_id=eq.' + encodeURIComponent(s.user.id) + '&tenant_id=eq.' + encodeURIComponent(tenant) + '&limit=1', s.access_token);
      }).then(function (rows) {
        var profile = rows && rows[0];
        if (!profile || profile.tenant_id !== tenant) return;
        state.account = { session: s, profile: profile };
        return select('customer_addresses', 'select=*&customer_id=eq.' + encodeURIComponent(profile.id) + '&order=is_default.desc,created_at.desc', s.access_token)
          .then(function (list) { state.addresses = Array.isArray(list) ? list : []; }, function () { state.addresses = []; })
          .then(function () {
            if (locked()) return;
            if (profile.name) setValue('name', profile.name);
            if (profile.email) setValue('email', profile.email);
            if (profile.phone) setValue('phone', profile.phone);
            var picker = field('saved');
            picker.innerHTML = '';
            state.addresses.forEach(function (a) {
              var o = document.createElement('option'); o.value = a.id; o.textContent = (a.label || '') + ' • ' + (a.comuna || ''); picker.appendChild(o);
            });
            var def = state.addresses.filter(function (a) { return a.is_default; })[0] || state.addresses[0];
            if (def) applySaved(def); else field('save_address').checked = true;
            paintDelivery();
          });
      });
    }).catch(function () { state.account = null; paintDelivery(); });
  }

  // ---- validation (the form's validators) ----------------------------------
  function setError(name, message) {
    var box = form.querySelector('[data-f="' + name + '"]');
    if (!box) return;
    var msg = box.querySelector('[data-msg]');
    box.classList.toggle('bad', !!message);
    msg.textContent = message || msg.dataset.helper || '';
  }
  var validators = {
    name: function (v) { return v ? null : 'El nombre es requerido'; },
    email: function (v) { return !v ? 'El correo es requerido' : EMAIL.test(v) ? null : 'Ingresa un correo válido'; },
    phone: function (v) { if (!v) return 'El teléfono es requerido'; var d = v.replace(/\D/g, ''); return d.length < 8 || d.length > 15 ? 'Ingresa un teléfono válido' : null; },
    password: function (v) {
      if (!field('create_account').checked) return null;
      var raw = field('password').value;
      if (!raw) return 'Por favor ingrese su contraseña';
      if (raw.length < 8) return 'La contraseña debe tener al menos 8 caracteres';
      if (!/[A-Za-z]/.test(raw) || !/[0-9]/.test(raw)) return 'Incluye al menos una letra y un número';
      return null;
    },
    password_confirm: function () {
      if (!field('create_account').checked) return null;
      var raw = field('password_confirm').value;
      if (!raw) return 'Por favor confirme su contraseña';
      return raw === field('password').value ? null : 'Las contraseñas no coinciden';
    },
    street: function (v) { return delivery() === 'pickup' || v ? null : 'La calle es requerida'; },
    comuna: function (v) { return delivery() === 'pickup' || v ? null : 'La comuna es requerida'; },
    region: function (v) { return delivery() === 'pickup' || v ? null : 'La región es requerida'; }
  };
  var validated = false;
  function validate() {
    validated = true;
    var first = null;
    Object.keys(validators).forEach(function (name) {
      var message = validators[name](value(name));
      setError(name, message);
      if (message && !first) first = field(name);
    });
    if (first) first.focus();
    return !first;
  }

  // ---- placing the order (_placeOrder) -------------------------------------
  function guard(event) { event.preventDefault(); event.returnValue = ''; }
  function holdPage(on) {
    if (on) window.addEventListener('beforeunload', guard); else window.removeEventListener('beforeunload', guard);
  }

  function buildOrder(q) {
    var l = state.lines, kind = delivery(), pickup = kind === 'pickup';
    var r = pickup ? null : orderAddress();
    var od = {
      tenant_id: tenant,
      checkout_idempotency_key: state.attempt,
      customer_email: value('email'),
      customer_name: value('name'),
      customer_phone: value('phone'),
      customer_address: pickup ? D.pickupAddress : (addressDisplay(r) || value('address')),
      delivery_type: kind,
      shipping_address_line1: pickup ? null : (r.street ? [r.street, r.number].filter(function (p) { return p; }).join(' ') : value('address')),
      shipping_address_line2: pickup ? null : r.apartment,
      shipping_city: pickup ? null : (r.city || r.comuna),
      shipping_state: pickup ? null : (r.region || null),
      shipping_postal_code: pickup ? null : r.postal,
      shipping_country: pickup ? null : 'Chile',
      subtotal: l.net,
      tax_amount: l.tax,
      shipping_quote_cost: q.shipping_gross,
      shipping_cost: q.shipping_gross,
      discount_amount: 0,
      total: q.item_gross + q.shipping_gross,
      status: 'pending',
      payment_status: 'pending',
      payment_method: payment(),
      customer_notes: value('notes') || null
    };
    var profile = state.account && state.account.profile;
    if (profile && profile.id != null) od.customer_id = profile.id;
    var items = l.items.map(function (it) {
      return { tenant_id: tenant, product_id: it.product_id, product_name: it.product_name, product_sku: it.product_sku, quantity: it.quantity, unit_price: it.unit_price, subtotal: it.subtotal };
    });
    return { od: od, items: items, address: r, pickup: pickup };
  }

  // The cart saved now must hold exactly what is being ordered
  // (captureDurableCheckoutRevision); its revision lets the cart lose
  // those units once, later, and nothing a later tab added.
  function captureRevision(items) {
    return cart.ensureRevision().then(function (snap) {
      var want = {};
      items.forEach(function (it) { want[it.product_id] = (want[it.product_id] || 0) + it.quantity; });
      var have = {};
      snap.lines.forEach(function (l) { have[l.id] = l.q; });
      var keys = Object.keys(want);
      if (!snap.revision || Object.keys(have).length !== keys.length || keys.some(function (k) { return have[k] !== want[k]; })) throw new Error('cart');
      return snap.revision;
    });
  }

  function sendOrder(snap) {
    state.creationAttempted = true;
    var token = snap.order_data.customer_id != null && state.account ? state.account.session.access_token : null;
    return rpc('create_public_online_order_with_access', { p_order_data: snap.order_data, p_order_items: snap.order_items }, token)
      .then(function (r) {
        var receipt = parseReceipt(r);
        if (!receipt) throw new Error('receipt');
        return receipt;
      });
  }

  // attachReceiptIfMatches
  function attachReceipt(receipt) {
    var current = readSnapshot();
    if (!current || current.idempotency_key !== state.snapshot.idempotency_key) throw new Error('receipt');
    if (current.receipt) {
      var same = current.receipt.order_id === receipt.order_id && current.receipt.access_token === receipt.access_token;
      if (!same) throw new Error('receipt');
      state.snapshot = current;
      return current;
    }
    current.receipt = receipt;
    saveSnapshot(current);
    state.snapshot = current;
    return current;
  }

  function placeOrder() {
    if (state.processing || state.storageDown) return;
    if (state.snapshot && state.snapshot.receipt) { resume(); return; }
    if (state.snapshot) { retry(); return; }
    if (!validate()) return;
    var l = state.lines;
    if (!l || !l.items.length) { toast('El carrito está vacío'); return; }
    if (l.outOfStock) { toast('Uno de los productos ya no está disponible. Vuelve al carrito para actualizarlo.'); return; }
    if (!l.valid) { toast(l.block || 'No podemos validar los impuestos de este carrito.', 8); return; }
    measureStep('shipping');
    measureStep('payment');
    var method = payment();
    state.processing = true; state.outcomeMessage = null; state.recoveryMessage = null;
    paintSummary();
    var order;
    rpc('get_public_checkout_capabilities', { p_tenant_id: tenant }).then(function (caps) {
      var ok = caps && Array.isArray(caps.methods) && caps.methods.some(function (m) { return m && m.code === method && m.available === true; });
      if (!ok) { toast('El medio de pago seleccionado ya no está disponible. Revisa las opciones antes de crear el pedido.', 7); throw 'stop'; }
      return quote(true);
    }, function () {
      toast('El medio de pago seleccionado ya no está disponible. Revisa las opciones antes de crear el pedido.', 7);
      throw 'stop';
    }).then(function (q) {
      if (!q || q.delivery_type !== delivery() || q.item_gross !== itemGross()) {
        toast('Necesitamos confirmar el costo de entrega antes de crear el pedido.');
        throw 'stop';
      }
      order = buildOrder(q);
      holdPage(true);
      return captureRevision(order.items).then(function (revision) {
        if (readSnapshot()) throw new Error('active');
        var snap = {
          v: 1, tenant_id: tenant, saved_at: nowIso(), idempotency_key: state.attempt,
          order_data: order.od, order_items: order.items,
          handoff: { payment_method: method, delivery_type: delivery() }, cart_revision: revision
        };
        saveSnapshot(snap);
        state.snapshot = parseSnapshot(ssRead(checkoutKey));
        if (!state.snapshot) throw new Error('snapshot');
        state.context = { address: order.address, pickup: order.pickup, saveAddress: !order.pickup && !!state.account && field('save_address').checked && !state.selected };
      }).catch(function (error) {
        if (error === 'stop') throw error;
        try { var s = readSnapshot(); if (s && !s.receipt && s.idempotency_key === state.attempt) ssClear(checkoutKey); } catch (e) { /* kept */ }
        state.snapshot = null;
        holdPage(false);
        var message = 'No pudimos guardar una recuperación segura en este dispositivo. El pedido no fue enviado. Recarga la aplicación e inténtalo nuevamente.';
        state.outcomeMessage = message;
        toast(message, 9);
        throw 'stop';
      });
    }).then(function () {
      return sendOrder(state.snapshot).then(function (receipt) {
        attachReceipt(receipt);
        return complete();
      }, function () {
        outcomeUnknown();
      });
    }).catch(function (error) {
      if (error !== 'stop') state.snapshot && state.snapshot.receipt ? postOrderRecovery() : outcomeUnknown();
    }).then(function () {
      state.processing = false;
      paintSummary();
    });
  }

  function retry() {
    state.processing = true; state.outcomeMessage = null; state.recoveryMessage = null;
    paintSummary();
    holdPage(true);
    sendOrder(state.snapshot).then(function (receipt) {
      attachReceipt(receipt);
      return complete();
    }).catch(function () {
      state.snapshot && state.snapshot.receipt ? postOrderRecovery() : outcomeUnknown();
    }).then(function () { state.processing = false; paintSummary(); });
  }

  function resume() {
    state.processing = true; state.outcomeMessage = null; state.recoveryMessage = null;
    paintSummary();
    complete().catch(postOrderRecovery).then(function () { state.processing = false; paintSummary(); });
  }

  // _completeCreatedOrder: keep the order's access, the optional account
  // and address tasks, then Mercado Pago or the order page.
  function complete() {
    var snap = state.snapshot, receipt = snap.receipt;
    saveOrderAccess(receipt);
    return postOrderTasks().then(function () {
      if (snap.handoff.payment_method === 'mercadopago') {
        return call('/functions/v1/mercadopago-create-preference', { order_id: receipt.order_id, order_access_token: receipt.access_token })
          .then(function (pref) {
            var init = pref && pref.init_point;
            if (typeof init !== 'string' || !init) throw new Error('init_point');
            holdPage(false);
            location.assign(init);
            return new Promise(function () {});
          });
      }
      return consumeCartOnce(receipt.order_id).then(function (outcome) {
        cart.badge();
        holdPage(false);
        location.assign('/pedido/' + encodeURIComponent(receipt.order_id));
        return new Promise(function () {});
      });
    });
  }

  function postOrderTasks() {
    var tasks = [];
    if (!state.accountTried) {
      state.accountTried = true;
      if (field('create_account').checked && !state.account) tasks.push(createAccount());
    }
    var ctx = state.context;
    if (!state.addressTried && ctx && ctx.saveAddress && ctx.address && state.account) {
      state.addressTried = true;
      tasks.push(saveAddress(ctx.address).catch(function () {
        toast('Tu pedido quedó guardado, pero no pudimos guardar la dirección en tu cuenta.', 7);
      }));
    }
    return Promise.all(tasks);
  }

  // gotrue-dart's signUp with the PKCE flow supabase_flutter uses: the
  // verifier where its storage keeps it, so the e-mail's link signs in.
  function createAccount() {
    var bytes = new Uint8Array(56); crypto.getRandomValues(bytes);
    var bin = ''; for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    var verifier = btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').split('=')[0];
    return crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier)).then(function (digest) {
      var d = new Uint8Array(digest), s = '';
      for (var k = 0; k < d.length; k++) s += String.fromCharCode(d[k]);
      var challenge = btoa(s).replace(/\+/g, '-').replace(/\//g, '_').split('=')[0];
      try { localStorage.setItem('flutter.supabase.auth.token-code-verifier', JSON.stringify(verifier)); } catch (e) { /* link still confirms */ }
      var redirect = encodeURIComponent(D.origin + '/cuenta/login?confirmed=true');
      return call('/auth/v1/signup?redirect_to=' + redirect, {
        email: value('email'), password: field('password').value,
        data: { account_type: 'public_store_customer', name: value('name'), phone: value('phone') },
        gotrue_meta_security: { captcha_token: null }, code_challenge: challenge, code_challenge_method: 's256'
      });
    }).then(function (r) {
      var signedIn = r && r.access_token && r.user && r.user.email_confirmed_at;
      toast(signedIn
        ? 'Cuenta creada. Desde Mi Cuenta podrás revisar pedidos, direcciones y servicios.'
        : 'Te enviamos un correo para activar tu cuenta. Tus pedidos quedarán asociados a este email.', 6);
    }, function () {
      toast('El pedido fue creado, pero no pudimos crear la cuenta automáticamente. Puedes iniciar sesión o recuperar acceso con este mismo correo.', 6);
    });
  }

  function saveAddress(r) {
    var acc = state.account;
    var label = value('address_label') || ('Dirección ' + (r.comuna || 'de entrega'));
    var full = addressDisplay({ street: r.street, number: r.number, apartment: r.apartment, comuna: r.comuna, city: r.city, region: r.region, chile: false }).toLowerCase();
    var exists = state.addresses.some(function (a) {
      return addressDisplay({ street: a.street_address, number: a.street_number, apartment: a.apartment, comuna: a.comuna, city: a.city, region: a.region, chile: false }).toLowerCase() === full;
    });
    if (exists) return Promise.resolve();
    var now = nowIso();
    return fetch(sbUrl + '/rest/v1/customer_addresses', {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + acc.session.access_token, 'content-type': 'application/json', prefer: 'return=minimal' },
      body: JSON.stringify({
        customer_id: acc.profile.id, label: label, recipient_name: value('name'), phone: value('phone'),
        street_address: r.street, street_number: r.number, apartment: r.apartment, comuna: r.comuna, city: r.city,
        region: r.region, postal_code: r.postal, additional_info: null, is_default: state.addresses.length === 0,
        created_at: now, updated_at: now, tenant_id: acc.profile.tenant_id
      })
    }).then(function (res) { if (!res.ok) throw new Error('address'); });
  }

  function postOrderRecovery() {
    state.outcomeMessage = null;
    state.recoveryMessage = 'Tu pedido ya quedó guardado. No pudimos completar el siguiente paso. Continúa para retomar el mismo pedido sin crear otro.';
    toast(state.recoveryMessage, 10);
  }
  function outcomeUnknown() {
    state.recoveryMessage = null;
    state.outcomeMessage = 'No pudimos confirmar el resultado del intento. Tu carrito sigue aquí. Reintenta con los mismos datos: si el pedido ya existe, recuperaremos ese mismo pedido.';
    toast(state.outcomeMessage, 10);
  }

  // ---- restoring an attempt of this tab (_restoreDurableCheckoutSession) --
  function restore() {
    var snap;
    try { snap = readSnapshot(); } catch (e) {
      state.storageDown = true;
      state.outcomeMessage = 'No pudimos revisar la recuperación segura de este checkout. Por protección, no enviaremos un pedido nuevo mientras el almacenamiento no esté disponible. Recarga la aplicación e inténtalo nuevamente.';
      return false;
    }
    if (!snap) return false;
    if (snap.receipt) {
      try { saveOrderAccess(snap.receipt); } catch (e) {
        state.storageDown = true;
        state.outcomeMessage = 'Recuperamos tu pedido, pero no pudimos verificar su acceso seguro en este dispositivo. Reinicia la aplicación e inténtalo nuevamente.';
        return false;
      }
    }
    state.snapshot = snap;
    state.restored = true;
    state.attempt = snap.idempotency_key;
    state.accountTried = true; state.addressTried = true;
    form.querySelector('input[name=delivery][value="' + snap.handoff.delivery_type + '"]').checked = true;
    var pay = form.querySelector('input[name=payment][value="' + snap.handoff.payment_method + '"]');
    if (pay) pay.checked = true;
    if (snap.receipt) {
      state.recoveryMessage = 'Recuperamos el pedido ya creado en esta sesión. Continúa para retomar el pago o la confirmación sin crear otro. Por seguridad no repetiremos tareas opcionales de cuenta o dirección.';
    } else {
      state.outcomeMessage = 'Recuperamos el intento seguro de esta sesión. Reintenta la confirmación para consultar el mismo pedido, sin reconstruir sus datos. Por seguridad no repetiremos tareas opcionales de cuenta o dirección.';
    }
    form.hidden = true;
    $('[data-co-restored]').hidden = false;
    show('full');
    paintSummary();
    return true;
  }

  // ---- wiring --------------------------------------------------------------
  form.addEventListener('change', function (event) {
    var t = event.target;
    if (t.name === 'delivery') {
      if (locked()) return;
      state.quote = null; state.quoteSig = null; state.quoteError = null;
      paintDelivery();
      if (validated) ['street', 'comuna', 'region'].forEach(function (n) { setError(n, validators[n](value(n))); });
      quote(false);
      if (t.value === 'pickup') measureStep('shipping');
    } else if (t.name === 'payment') {
      paintButton();
      measureStep('payment');
    } else if (t.name === 'create_account') {
      $('[data-co-password]').hidden = !t.checked;
      if (!t.checked) { setError('password', null); setError('password_confirm', null); }
    } else if (t.name === 'saved') {
      var picked = state.addresses.filter(function (a) { return a.id === t.value; })[0];
      if (picked) applySaved(picked);
    }
  });
  form.addEventListener('input', function (event) {
    var t = event.target;
    if (validated && validators[t.name]) setError(t.name, validators[t.name](value(t.name)));
    if (t.name === 'address') {
      if (!t.value.trim()) { state.selected = null; state.resolved = null; paintDelivery(); }
      suggest();
    }
  });
  form.addEventListener('submit', function (event) { event.preventDefault(); });
  var address = field('address');
  address.setAttribute('role', 'combobox');
  address.setAttribute('aria-controls', 'co-sugs');
  address.setAttribute('aria-expanded', 'false');
  address.addEventListener('keydown', function (event) {
    if (sugList.hidden || !sugItems.length) return;
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      sugIndex = (sugIndex + (event.key === 'ArrowDown' ? 1 : -1) + sugItems.length) % sugItems.length;
      $$('[data-co-sugs] [role=option]').forEach(function (li, i) { li.setAttribute('aria-selected', String(i === sugIndex)); });
      address.setAttribute('aria-activedescendant', 'co-sug-' + sugIndex);
    } else if (event.key === 'Enter' && sugIndex >= 0) {
      event.preventDefault(); pickSuggestion(sugItems[sugIndex]);
    } else if (event.key === 'Escape') { closeSugs(); }
  });
  sugList.addEventListener('mousedown', function (event) {
    var li = event.target.closest && event.target.closest('[role=option]');
    if (!li) return;
    event.preventDefault();
    pickSuggestion(sugItems[Number(li.dataset.index)]);
  });
  address.addEventListener('blur', function () { setTimeout(closeSugs, 150); });
  root.addEventListener('click', function (event) {
    var b = event.target.closest && event.target.closest('[data-act]');
    if (!b || b.disabled) return;
    var act = b.dataset.act;
    if (act === 'place') placeOrder();
    else if (act === 'requote') quote(true);
    else if (act === 'eye') {
      var show = field('password').type === 'password';
      field('password').type = show ? 'text' : 'password';
      field('password_confirm').type = show ? 'text' : 'password';
      b.innerHTML = show ? root.dataset.eyeOff : root.dataset.eyeOn;
      b.setAttribute('aria-label', show ? 'Ocultar contraseña' : 'Mostrar contraseña');
    }
  });

  // An old Mercado Pago return to the checkout (`?status=failure&pedido=`).
  (function () {
    var params = new URLSearchParams(location.search), status = params.get('status');
    if (!status) return;
    var order = params.get('pedido') || params.get('order');
    if (status === 'failure') toast(order ? 'El pago del pedido ' + order + ' fue cancelado. Puedes intentarlo nuevamente.' : 'El pago no se completó. Inténtalo nuevamente.');
    else if (status === 'pending' && order) toast('El pago del pedido ' + order + ' está pendiente. Te avisaremos cuando se confirme.');
    history.replaceState(history.state, '', location.pathname);
  })();

  call('/functions/v1/google-places-proxy', { action: 'status', tenantId: tenant }).then(function (r) {
    state.places = !!(r && r.enabled === true);
  }, function () { state.places = false; }).then(function () { state.placesUnknown = false; paintDelivery(); });
  state.placesUnknown = true;
  paintDelivery();
  if (!restore()) {
    loadLines().then(function () { loadAccount(); });
  }
  if (state.storageDown) { show('full'); paintSummary(); }
  window.addEventListener('pageshow', function (event) { if (event.persisted && !state.snapshot) loadLines(); });
})(document.querySelector('[data-co]'));
''';
