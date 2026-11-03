/// What `/cotizacion` does in the browser. The lines the visitor gathers live
/// in `localStorage` (`vinabike.quote.lines`, `[{id, q}]`) like the cart; a
/// sent quote is remembered by its number and its link (`vinabike.quote.sent`)
/// so «Tu cotización» opens it again. Every state comes from the database's
/// commands (20261102041700, 20261102175500): `request_public_customer_quote_v1`
/// with the customer's session, `get_public_customer_quote_v1`,
/// `respond_public_customer_quote_v1`, `update_public_customer_quote_notify_v1`,
/// `open_my_customer_quote_v1` and `get_public_on_order_terms_v1`. Opening the
/// link only reads; accepting, changing or rejecting is always a click on
/// this page, so a mail scanner that follows the link answers nothing.
///
/// Sending needs the account (`window.vinabikeSession`): its name, email and
/// phone answer the quote, and the customer picks the notices — email,
/// WhatsApp or both, remembered for the next one (`vinabike.quote.notify`).
///
/// Accepting asks only what an order needs (20261103010000): pickup or
/// shipping (priced like the checkout, `quote_public_online_shipping`) and
/// Mercado Pago or transfer (`get_public_checkout_capabilities`).
/// `accept_public_customer_quote_v1` turns the offer into the web order; its
/// access goes into the checkout's records (`vinabikeCheckoutRecords`) and the
/// customer pays where every order is paid: Mercado Pago, or `/pedido/<id>`
/// with the transfer details. An accepted quote shows its order, and
/// `open_public_customer_quote_order_v1` opens it again from the link.
const quotePageScript = r'''
(function () {
  var root = document.querySelector('[data-qt]');
  if (!root) return;
  var d = root.dataset;
  var tenant = d.tenant, sbUrl = d.sbUrl, sbKey = d.sbKey;
  var LINES = 'vinabike.quote.lines', SENT = 'vinabike.quote.sent', NOTIFY = 'vinabike.quote.notify';
  var AFTER = 'vb-after-login';
  function $(sel) { return root.querySelector(sel); }
  function text(v) { return v == null ? '' : String(v).trim(); }
  function esc(v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
  function money(v) {
    var n = Math.round(Number(v) || 0);
    return '$' + String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  }
  function when(v) {
    if (!v) return '';
    try {
      return new Date(v).toLocaleString('es-CL', { timeZone: 'America/Santiago', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
    } catch (e) { return ''; }
  }
  function load(key, fallback) {
    try { var v = JSON.parse(localStorage.getItem(key) || 'null'); return v == null ? fallback : v; } catch (e) { return fallback; }
  }
  function save(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) {} }
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16); crypto.getRandomValues(b);
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    var h = Array.prototype.map.call(b, function (x) { return (x + 256).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  var toastTimer = null;
  function toast(message, bad) {
    var el = $('[data-qt-toast]');
    el.textContent = message; el.classList.toggle('bad', !!bad); el.hidden = false;
    clearTimeout(toastTimer); toastTimer = setTimeout(function () { el.hidden = true; }, 4500);
  }
  // [token]: the customer's session for the commands that need the account.
  function call(fn, body, token) {
    return fetch(sbUrl + '/rest/v1/rpc/' + fn, {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + (token || sbKey), 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify(body)
    }).then(function (r) {
      return r.text().then(function (t) {
        var data = null;
        try { data = t ? JSON.parse(t) : null; } catch (e) { data = null; }
        if (!r.ok) { var err = new Error((data && data.message) || ('http ' + r.status)); err.data = data || {}; err.status = r.status; throw err; }
        return data;
      });
    });
  }
  function remember(number, token) {
    var sent = load(SENT, []).filter(function (s) { return s && s.t !== token && (!number || s.n !== number); });
    sent.unshift({ n: number || '', t: token, at: new Date().toISOString() });
    save(SENT, sent.slice(0, 10));
  }
  function phoneOk(v) { var n = String(v || '').replace(/[^0-9]/g, ''); return n.length >= 8 && n.length <= 15; }
  function emailOk(v) { return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(text(v)); }
  // «correo y WhatsApp», «correo» or «WhatsApp», as the customer chose.
  function notices(q, joiner) {
    var list = [];
    if (q.notifyEmail) list.push('correo');
    if (q.notifyWhatsapp) list.push('WhatsApp');
    return list.length ? list.join(joiner || ' y ') : 'correo';
  }
  function leadText(min, max) {
    if (min == null) return '';
    return 'llega en ' + (min === max || max == null ? min : min + ' a ' + max) + ' días hábiles';
  }
  // The checkout's records keep the order's access: the order page opens it.
  var R = window.vinabikeCheckoutRecords ? window.vinabikeCheckoutRecords(tenant, window.vinabikeCart) : null;

  // ---- the customer's account -----------------------------------------------
  // The session is the store's; the account's row says who answers the quote.
  var account = null;
  function session(renew) {
    var s = window.vinabikeSession;
    if (!s || !s.read || !s.read()) return Promise.resolve(null);
    return (renew ? s.renew() : s.current()).catch(function () { return null; });
  }
  function customerRow(s) {
    return fetch(sbUrl + '/rest/v1/customers?select=id,name,email,phone,tenant_id,auth_user_id&auth_user_id=eq.' +
      encodeURIComponent(s.user.id) + '&tenant_id=eq.' + encodeURIComponent(tenant) + '&limit=1', {
      headers: { apikey: sbKey, authorization: 'Bearer ' + s.access_token, accept: 'application/json' }
    }).then(function (r) {
      if (r.status === 401) { var err = new Error('expired'); err.status = 401; throw err; }
      return r.ok ? r.json() : [];
    }).then(function (rows) {
      var row = rows && rows[0];
      return row && row.tenant_id === tenant && row.auth_user_id === s.user.id ? row : null;
    });
  }
  function loadAccount(renew) {
    return session(renew).then(function (s) {
      if (!s) return null;
      return customerRow(s).then(function (row) {
        if (row) return row;
        // A session from before the store's customer existed is completed
        // here, as the checkout does.
        return call('provision_current_public_store_customer', { p_tenant_id: tenant }, s.access_token)
          .then(function () { return customerRow(s); }, function () { return null; });
      }).then(function (row) { return row ? { session: s, row: row } : null; });
    }).catch(function (err) {
      return err && err.status === 401 && !renew ? loadAccount(true) : null;
    });
  }
  function show(name) {
    ['loading', 'build', 'empty', 'view'].forEach(function (n) {
      var el = $('[data-qt-' + n + ']'); if (el) el.hidden = n !== name;
    });
  }

  // ---- the quote being put together -------------------------------------
  var lines = load(LINES, []).filter(function (l) { return l && l.id && l.q > 0; });
  var drawn = [];
  function persist() { save(LINES, lines.map(function (l) { return { id: l.id, q: l.q }; })); }

  function kindOf(line, terms) {
    if (line.stock >= line.q) return { kind: 'in_stock', label: 'En stock' };
    var t = terms[line.id];
    if (t) {
      var lead = t.leadDaysMin === t.leadDaysMax ? t.leadDaysMin : t.leadDaysMin + ' a ' + t.leadDaysMax;
      return { kind: 'on_order', label: 'A pedido · llega en ' + lead + ' días hábiles' };
    }
    return { kind: 'to_confirm', label: line.stock > 0 ? 'Hay ' + line.stock + ', el resto por confirmar' : 'Disponibilidad por confirmar' };
  }

  function drawLines(terms) {
    var list = $('[data-qt-lines]');
    var icon = root.dataset.iconPhoto || '';
    list.innerHTML = drawn.map(function (line) {
      var k = kindOf(line, terms);
      return '<li class="qt-line" data-id="' + esc(line.id) + '">' +
        '<a class="qt-ph" href="' + esc(line.url) + '" tabindex="-1" aria-hidden="true">' + (line.img ? '<img src="' + esc(line.img) + '" alt="" loading="lazy">' : icon) + '</a>' +
        '<div><a class="qt-name" href="' + esc(line.url) + '">' + esc(line.title) + '</a>' +
        '<p class="qt-meta">' + (line.sku ? 'SKU ' + esc(line.sku) + ' · ' : '') + 'Precio publicado ' + money(line.price) + '</p>' +
        '<span class="qt-tag" data-kind="' + k.kind + '">' + esc(k.label) + '</span></div>' +
        '<div class="qt-side"><div class="qt-qty"><button type="button" data-step="-1" aria-label="Quitar una unidad">−</button>' +
        '<output aria-live="polite">' + line.q + '</output>' +
        '<button type="button" data-step="1" aria-label="Agregar una unidad">+</button></div>' +
        '<button type="button" class="qt-rm" data-rm>Quitar</button></div></li>';
    }).join('');
    var onOrder = drawn.some(function (l) { return kindOf(l, terms).kind !== 'in_stock'; });
    $('[data-qt-ref]').textContent = onOrder
      ? 'El precio publicado es la referencia. En la oferta va el precio y el plazo confirmados de cada producto.'
      : 'Los productos están en stock: la oferta confirma el precio y el retiro o despacho.';
  }

  function refreshBuilder() {
    if (!lines.length) { show('empty'); return Promise.resolve(); }
    var l = lines.map(function (x) { return encodeURIComponent(x.id) + ':' + x.q; }).join(',');
    return fetch(root.dataset.linesUrl + '?l=' + l, { headers: { accept: 'application/json' } })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var byId = {};
        (data.lines || []).forEach(function (x) { byId[x.id] = x; });
        drawn = lines.map(function (x) {
          var d = byId[x.id]; if (!d) return null;
          return { id: x.id, q: x.q, title: d.title, sku: d.sku, url: d.url, img: d.img, price: d.price, stock: d.stock };
        }).filter(Boolean);
        if (drawn.length !== lines.length) {
          lines = drawn.map(function (d) { return { id: d.id, q: d.q }; }); persist();
        }
        if (!drawn.length) { show('empty'); return; }
        return call('get_public_on_order_terms_v1', { p_tenant_id: tenant, p_product_ids: drawn.map(function (d) { return d.id; }) })
          .catch(function () { return {}; })
          .then(function (terms) { drawLines(terms || {}); show('build'); });
      })
      .catch(function () { toast('No pudimos cargar tu cotización. Revisa tu conexión.', true); show('build'); });
  }

  $('[data-qt-lines]').addEventListener('click', function (e) {
    var li = e.target.closest('.qt-line'); if (!li) return;
    var id = li.dataset.id;
    var line = lines.filter(function (x) { return x.id === id; })[0]; if (!line) return;
    if (e.target.closest('[data-rm]')) {
      lines = lines.filter(function (x) { return x.id !== id; });
    } else {
      var step = e.target.closest('[data-step]'); if (!step) return;
      line.q = Math.max(1, Math.min(99, line.q + Number(step.dataset.step)));
    }
    persist(); refreshBuilder();
  });

  // ---- sending it ---------------------------------------------------------
  var form = $('[data-qt-form]');
  var sending = false;
  root.querySelectorAll('[data-qt-profile]').forEach(function (a) { a.href = d.profileUrl; });
  var login = $('[data-qt-login]');
  login.href = d.loginUrl;
  // Back from entering, the page comes back here with the lines it kept.
  login.addEventListener('click', function () {
    try { sessionStorage.setItem(AFTER, location.pathname); } catch (e) { /* the account opens instead */ }
  });
  function drawBox() {
    $('[data-qt-checking]').hidden = true;
    $('[data-qt-signin]').hidden = !!account;
    form.hidden = !account;
    if (!account) return;
    var row = account.row, f = form.elements;
    var hasEmail = emailOk(row.email), hasPhone = phoneOk(row.phone);
    $('[data-qt-who-name]').textContent = text(row.name) || 'Tu cuenta';
    $('[data-qt-who-line]').textContent = [hasEmail ? text(row.email) : '', hasPhone ? text(row.phone) : ''].filter(Boolean).join(' · ');
    // The last choice, or email: it always reaches the customer and needs
    // nobody at the shop to send it.
    var kept = load(NOTIFY, null) || {};
    var byEmail = (typeof kept.e === 'boolean' ? kept.e : true) && hasEmail;
    var byWhatsapp = !!kept.w && hasPhone;
    if (!byEmail && !byWhatsapp) { byEmail = hasEmail; byWhatsapp = !hasEmail && hasPhone; }
    f['notify_email'].checked = byEmail; f['notify_email'].disabled = !hasEmail;
    f['notify_whatsapp'].checked = byWhatsapp; f['notify_whatsapp'].disabled = !hasPhone;
    $('[data-qt-nophone]').hidden = hasPhone;
  }
  function refreshAccount() {
    return loadAccount(false).then(function (a) { account = a; drawBox(); });
  }
  // Back from editing the data in the account, the page shows the new ones.
  window.addEventListener('pageshow', function (e) { if (e.persisted) refreshAccount(); });
  function fail(message) {
    var err = $('[data-qt-err]'); err.textContent = message || ''; err.hidden = !message;
  }
  form.addEventListener('change', function () { fail(''); });
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (sending) return;
    if (!account) { drawBox(); return; }
    var f = form.elements;
    var byEmail = f['notify_email'].checked && !f['notify_email'].disabled;
    var byWhatsapp = f['notify_whatsapp'].checked && !f['notify_whatsapp'].disabled;
    if (!byEmail && !byWhatsapp) return fail('Elige cómo quieres que te avisemos.');
    if (!lines.length) return fail('Agrega al menos un producto.');
    fail('');
    sending = true;
    var button = $('[data-qt-send]'); button.disabled = true; button.textContent = 'Enviando…';
    // One key per sending: a retry after a dropped connection is the same quote.
    var key = form.dataset.key || (form.dataset.key = uuid());
    var body = {
      p_tenant_id: tenant,
      p_request: {
        request_idempotency_key: key, notify_email: byEmail, notify_whatsapp: byWhatsapp,
        customer_notes: text(f['notes'].value) || null,
        items: lines.map(function (l) { return { product_id: l.id, quantity: l.q }; })
      }
    };
    var attempt = function (renewed) {
      return call('request_public_customer_quote_v1', body, account.session.access_token).catch(function (err) {
        if (err.status !== 401 || renewed) throw err;
        return session(true).then(function (s) {
          if (!s) throw err;
          account.session = s;
          return attempt(true);
        });
      });
    };
    attempt(false).then(function (receipt) {
      save(NOTIFY, { e: byEmail, w: byWhatsapp });
      remember(receipt.quote_number, receipt.access_token);
      lines = []; persist(); delete form.dataset.key; f['notes'].value = '';
      openQuote(receipt.access_token, true);
    }).catch(function (err) {
      var code = (err.data && err.data.message) || '';
      var detail = (err.data && err.data.details) || '';
      if (err.status === 401 || code === 'quote_account_required') {
        account = null; drawBox();
        toast('Entra a tu cuenta para enviarla.', true);
      } else if (code === 'quote_contact_invalid') {
        fail({
          notify: 'Elige cómo quieres que te avisemos.',
          customer_phone: 'Tu cuenta no tiene un teléfono válido para WhatsApp. Agrégalo en tu cuenta o elige correo.',
          customer_email: 'Tu cuenta no tiene un correo válido. Revísalo en tu cuenta.',
          customer_name: 'Agrega tu nombre en tu cuenta para enviarla.',
          customer_notes: 'El comentario es muy largo.'
        }[detail] || 'Revisa tus datos en tu cuenta.');
      } else if (code === 'quote_product_not_available') {
        fail('Un producto ya no está disponible en el sitio. Actualizamos la lista.');
        refreshBuilder();
      } else if (code === 'quote_rate_limited') {
        fail('Recibimos varias cotizaciones tuyas hoy. Escríbenos si necesitas otra.');
      } else {
        fail('No se pudo enviar. Revisa tu conexión e inténtalo de nuevo.');
      }
    }).then(function () { sending = false; button.disabled = false; button.textContent = 'Pedir cotización'; });
  });

  // ---- a sent quote ----------------------------------------------------------
  var STATUS = {
    confirming: 'Confirmando disponibilidad',
    offered: 'Oferta lista',
    accepted: 'Aceptada',
    rejected: 'Rechazada',
    expired: 'Vencida',
    cancelled: 'Anulada'
  };
  var AVAIL = { in_stock: 'En stock', on_order: 'A pedido', unavailable: 'No disponible', pending: 'Por confirmar' };
  var HISTORY = {
    requested: 'Pediste la cotización', offer_sent: 'Te enviamos la oferta', accepted: 'Aceptaste la oferta',
    changes_requested: 'Pediste cambios', rejected: 'Rechazaste la oferta', expired: 'La oferta venció', cancelled: 'La cotización se anuló',
    order_paid: 'Pagaste el pedido', order_sale_issued: 'Llegó lo que venía a pedido', order_ready: 'Tu pedido quedó listo para retiro',
    order_shipped: 'Despachamos tu pedido', order_delivered: 'Pedido entregado', order_cancelled: 'El pedido se anuló',
    order_refunded: 'Te devolvimos el pago'
  };
  var REGIONS = ['Arica y Parinacota', 'Tarapacá', 'Antofagasta', 'Atacama', 'Coquimbo', 'Valparaíso', 'Metropolitana',
    "O'Higgins", 'Maule', 'Ñuble', 'Biobío', 'La Araucanía', 'Los Ríos', 'Los Lagos', 'Aysén', 'Magallanes'];
  var current = { token: null, data: null, mode: 'view' };

  function lineCell(l) {
    var lead = l.availability === 'on_order' && l.leadDaysMin != null
      ? ' · llega en ' + (l.leadDaysMin === l.leadDaysMax ? l.leadDaysMin : l.leadDaysMin + ' a ' + l.leadDaysMax) + ' días hábiles' : '';
    var partial = l.quantity > 0 && l.quantity < l.quantityRequested ? ' · ' + l.quantity + ' de ' + l.quantityRequested : '';
    return '<strong>' + esc(l.name) + '</strong>' +
      '<br><span class="qt-tag" data-kind="' + esc(l.availability) + '">' + esc((AVAIL[l.availability] || '') + partial + lead) + '</span>' +
      (l.note ? '<p class="qt-note">' + esc(l.note) + '</p>' : '');
  }

  // The notices of a sent quote: what the customer chose, and the choice
  // again while the shop still writes to them.
  function noticeBlock(q, acts) {
    if (current.mode === 'notify') {
      return '<div class="qt-notice-edit"><fieldset class="qt-notify"><legend>¿Por dónde te avisamos?</legend><div class="qt-notify-row">' +
        '<label><input type="checkbox" data-notify="email"' + (q.notifyEmail ? ' checked' : '') + (q.canEmail ? '' : ' disabled') + '><span>Correo</span></label>' +
        '<label><input type="checkbox" data-notify="whatsapp"' + (q.notifyWhatsapp ? ' checked' : '') + (q.canWhatsapp ? '' : ' disabled') + '><span>WhatsApp</span></label></div>' +
        (q.canWhatsapp ? '' : '<p class="qt-hint">Para recibirla por WhatsApp, agrega tu teléfono en <a href="' + esc(d.profileUrl) + '">tu cuenta</a>.</p>') +
        '</fieldset><div class="qt-acts"><button class="qt-btn fill" data-act="save-notify">Guardar</button><button class="qt-btn text" data-act="cancel-change">Volver</button></div></div>';
    }
    return '<p class="qt-notice">Avisos por ' + esc(notices(q)) +
      (acts.changeNotify ? ' <button class="qt-btn text" data-act="notify">Cambiar</button>' : '') + '</p>';
  }

  function drawQuote() {
    var data = current.data, q = data.quote || {}, o = data.offer, acts = data.actions || {};
    var mode = current.mode;
    var view = $('[data-qt-view]');
    var html = '<p class="qt-kick">Cotización ' + esc(q.number) + '</p>' +
      '<h1 class="qt-title">' + (q.status === 'offered' ? 'Tu oferta está lista' : q.status === 'accepted' ? 'Oferta aceptada' : q.status === 'confirming' ? 'Estamos confirmando tu cotización' : esc(STATUS[q.status] || 'Tu cotización')) + '</h1>' +
      '<div class="qt-status"><span class="qt-pill" data-s="' + esc(q.status) + '">' + esc(STATUS[q.status] || q.status) + '</span>' +
      (q.status === 'offered' && q.expiresAt ? '<span class="qt-when">Vale hasta el ' + esc(when(q.expiresAt)) + '</span>' : '') +
      (q.status === 'confirming' ? '<span class="qt-when">Te avisamos por ' + esc(notices(q)) + ' cuando esté lista.</span>' : '') + '</div>' +
      (q.status === 'confirming' || q.status === 'offered' || q.status === 'accepted' ? noticeBlock(q, acts) : '');

    if (o && o.lines) {
      var changing = mode === 'change';
      // While a new offer is prepared, the replaced one is shown as such.
      var stale = o.status === 'superseded' && q.status === 'confirming';
      html += '<div class="qt-card' + (stale ? ' qt-stale' : '') + '">' +
        (stale ? '<p class="qt-note" style="margin:0 0 12px">Esta es la oferta anterior. Estamos preparando una nueva con tus cambios.</p>' : '') +
        '<table class="qt-offer"><thead><tr><th>Producto</th><th class="num">Precio</th><th class="num">' + (changing ? 'Cantidad' : 'Cant.') + '</th><th class="num">Total</th></tr></thead><tbody>' +
        o.lines.map(function (l) {
          var qty = changing
            ? '<span class="qt-change"><input type="number" min="0" max="99" value="' + (l.quantity > 0 ? l.quantity : 0) + '" data-line="' + l.lineNo + '" aria-label="Cantidad de ' + esc(l.name) + '"></span>'
            : String(l.quantity);
          return '<tr><td>' + lineCell(l) + '</td><td class="num">' + (l.unitPrice != null ? money(l.unitPrice) : '—') + '</td><td class="num">' + qty + '</td><td class="num">' + (l.lineTotal != null ? money(l.lineTotal) : '—') + '</td></tr>';
        }).join('') + '</tbody></table>' +
        '<div class="qt-totals"><div><span>Neto</span><span>' + money(o.subtotal) + '</span></div><div><span>IVA</span><span>' + money(o.taxAmount) + '</span></div>' +
        '<div class="total"><span>Total</span><span>' + money(o.total) + '</span></div></div>' +
        (o.notes ? '<p class="qt-note">' + esc(o.notes) + '</p>' : '');
      // One question at a time: the three answers, or the one being given.
      if (acts.accept && mode === 'view') {
        var onOrder = o.lines.some(function (l) { return l.availability === 'on_order' && l.quantity > 0; });
        html += (onOrder && acts.onOrderPrepayPercent > 0 ? '<p class="qt-note">Lo que es a pedido se paga ' + (acts.onOrderPrepayPercent >= 100 ? 'por adelantado' : 'con un abono del ' + acts.onOrderPrepayPercent + ' %') + ' antes de pedirlo.</p>' : '') +
          '<div class="qt-acts"><button class="qt-btn fill" data-act="accept">Aceptar oferta</button>' +
          '<button class="qt-btn line" data-act="change">Pedir cambios</button>' +
          '<button class="qt-btn text" data-act="reject">Rechazar</button></div>';
      }
      if (changing) {
        html += '<label class="qt-field" style="margin-top:18px"><span>¿Qué cambiamos?</span><textarea rows="3" maxlength="2000" data-change-note placeholder="Por ejemplo: sólo 2 cámaras, o la misma medida en otra marca."></textarea></label>' +
          '<div class="qt-acts"><button class="qt-btn fill" data-act="send-change">Enviar cambios</button><button class="qt-btn text" data-act="cancel-change">Volver</button></div>';
      }
      if (mode === 'reject') {
        html += '<label class="qt-field" style="margin-top:18px"><span>¿Nos cuentas por qué? <i>(opcional)</i></span><textarea rows="2" maxlength="2000" data-reject-note></textarea></label>' +
          '<div class="qt-acts"><button class="qt-btn fill" data-act="send-reject">Rechazar oferta</button><button class="qt-btn text" data-act="cancel-change">Volver</button></div>';
      }
      if (mode === 'accept') html += acceptPanel(o);
      html += '</div>';
    } else {
      html += '<div class="qt-card"><table class="qt-offer"><thead><tr><th>Lo que pediste</th><th></th><th class="num">Cant.</th></tr></thead><tbody>' +
        (data.requested || []).map(function (l) {
          return '<tr><td><strong>' + esc(l.name) + '</strong>' + (l.sku ? '<p class="qt-note">SKU ' + esc(l.sku) + '</p>' : '') + '</td><td></td><td class="num">' + l.quantity + '</td></tr>';
        }).join('') + '</tbody></table></div>';
    }

    if (data.order) {
      html += orderBlock(data.order, acts);
    } else if (q.status === 'accepted') {
      html += '<div class="qt-card"><h2 class="qt-h2">Lo que sigue</h2><p class="qt-note">Te escribimos por ' + esc(notices(q, ' o ')) + ' para coordinar el pago y la entrega.</p></div>';
    }
    var history = data.history || [];
    if (history.length) {
      html += '<div class="qt-card"><h2 class="qt-h2">Historia</h2><ul class="qt-history">' +
        history.slice().reverse().map(function (h) { return '<li><span>' + esc(HISTORY[h.type] || h.type) + '</span><time>' + esc(when(h.at)) + '</time></li>'; }).join('') + '</ul></div>';
    }
    // The offer as a PDF, the one the shop sends from the ERP: only an offer
    // that stands (valid, accepted or expired), never the one being replaced.
    var canPdf = !!(o && o.lines && o.lines.length) && !(o.status === 'superseded' && q.status === 'confirming') &&
      ['offered', 'accepted', 'expired'].indexOf(q.status) >= 0;
    html += '<p class="qt-link">Con este enlace vuelves a tu cotización desde cualquier equipo. <button class="qt-btn text" data-act="copy">Copiar enlace</button>' +
      (canPdf ? ' <button class="qt-btn text" data-act="pdf">Descargar PDF</button>' : '') + '</p>';
    html += '<p class="qt-others"><a href="' + esc(d.accountUrl) + '">Todas tus cotizaciones en Mi cuenta</a>' +
      (lines.length ? ' · <a href="#" data-act="builder">La que estás armando (' + lines.length + ')</a>' : '') + '</p>';
    view.innerHTML = html;
    show('view');
    if (mode === 'accept' && o) wireAccept(o);
  }

  // ---- accepting: how it arrives, how it is paid, one button ----------------
  function choice(name, value, title, sub, checked) {
    return '<label><input type="radio" name="' + name + '" value="' + value + '"' + (checked ? ' checked' : '') +
      '><span><b>' + esc(title) + '</b><small>' + esc(sub) + '</small></span></label>';
  }
  function acceptPanel(o) {
    var onOrder = o.lines.some(function (l) { return l.availability === 'on_order' && l.quantity > 0; });
    return '<div class="qt-accept" data-qt-accept>' +
      '<h2 class="qt-h2">¿Cómo lo recibes?</h2>' +
      '<div class="qt-choice" role="radiogroup" aria-label="Entrega">' +
        choice('qt-delivery', 'pickup', 'Retiro en el taller', 'Sin costo', true) +
        choice('qt-delivery', 'shipping', 'Despacho a domicilio', 'Según tu región', false) + '</div>' +
      '<div class="qt-address" data-qt-address hidden>' +
        '<label class="qt-field"><span>Dirección</span><input name="line1" autocomplete="address-line1" maxlength="200" placeholder="Calle y número"></label>' +
        '<label class="qt-field"><span>Depto / oficina <i>(opcional)</i></span><input name="line2" autocomplete="address-line2" maxlength="200"></label>' +
        '<div class="qt-pair"><label class="qt-field"><span>Comuna</span><input name="city" autocomplete="address-level2" maxlength="120"></label>' +
        '<label class="qt-field"><span>Región</span><select name="region" autocomplete="address-level1"><option value="">Elige tu región</option>' +
          REGIONS.map(function (r) { return '<option>' + esc(r) + '</option>'; }).join('') + '</select></label></div></div>' +
      '<h2 class="qt-h2">¿Cómo pagas?</h2>' +
      '<div class="qt-choice" role="radiogroup" aria-label="Pago">' +
        choice('qt-pay', 'mercadopago', 'Mercado Pago', 'Tarjeta de crédito o débito', false) +
        choice('qt-pay', 'transfer', 'Transferencia', 'Te damos los datos al confirmar', false) + '</div>' +
      '<div class="qt-totals" data-qt-sum></div>' +
      (onOrder ? '<p class="qt-note">Lo que viene a pedido se paga ahora, así lo pedimos al tiro. Te avisamos cuando llegue.</p>' : '') +
      '<p class="qt-err" data-qt-accept-err hidden></p>' +
      '<div class="qt-acts"><button class="qt-btn fill" data-act="send-accept" disabled>Aceptar y pagar</button>' +
      '<button class="qt-btn text" data-act="cancel-change">Volver</button></div></div>';
  }

  var accepting = null;
  function wireAccept(o) {
    var panel = $('[data-qt-accept]'); if (!panel) return;
    if (!accepting || accepting.offer !== o.id) accepting = { offer: o.id, key: uuid(), ship: null, shipError: '', quoting: false, sending: false, seq: 0 };
    function field(n) { return panel.querySelector('[name=' + n + ']'); }
    function delivery() { var c = panel.querySelector('[name=qt-delivery]:checked'); return c ? c.value : 'pickup'; }
    function pay() { var c = panel.querySelector('[name=qt-pay]:checked'); return c ? c.value : ''; }
    function cost() { return delivery() === 'shipping' ? (accepting.ship ? accepting.ship.gross : null) : 0; }
    function paint() {
      var ship = delivery() === 'shipping', s = accepting.ship, c = cost();
      $('[data-qt-address]').hidden = !ship;
      var shipText = !ship ? 'Sin costo' : accepting.quoting ? 'Calculando…'
        : s ? money(s.gross) + (s.max ? ' · ' + (s.min === s.max ? s.min : s.min + ' a ' + s.max) + ' días hábiles' : '')
        : accepting.shipError || 'Elige tu región';
      panel.querySelector('[data-qt-sum]').innerHTML =
        '<div><span>Productos</span><span>' + money(o.total) + '</span></div>' +
        '<div><span>' + (ship ? 'Despacho' : 'Retiro en el taller') + '</span><span>' + esc(shipText) + '</span></div>' +
        '<div class="total"><span>Total</span><span>' + (c == null ? '—' : money(o.total + c)) + '</span></div>';
      var btn = panel.querySelector('[data-act=send-accept]');
      btn.textContent = accepting.sending ? 'Creando tu pedido…'
        : (pay() === 'transfer' ? 'Aceptar y transferir' : 'Aceptar y pagar') + (c == null ? '' : ' · ' + money(o.total + c));
      btn.disabled = accepting.sending || !pay() || c == null;
    }
    function quoteShipping() {
      var region = field('region').value, mine = ++accepting.seq;
      accepting.ship = null; accepting.shipError = '';
      if (delivery() !== 'shipping' || !region) { accepting.quoting = false; paint(); return; }
      accepting.quoting = true; paint();
      call('quote_public_online_shipping', { p_tenant_id: tenant, p_delivery_type: 'shipping', p_item_gross: o.total, p_country_code: 'CL', p_region: region })
        .then(function (r) {
          if (mine !== accepting.seq) return;
          accepting.ship = { gross: Math.round(Number(r.shipping_gross) || 0), min: r.estimated_min_business_days, max: r.estimated_max_business_days };
        })
        .catch(function (err) {
          if (mine !== accepting.seq) return;
          var said = (err.data && err.data.message) || '';
          accepting.shipError = /^(Por ahora no despachamos|No reconocemos la región)/.test(said) ? said : 'No pudimos calcular el despacho';
        })
        .then(function () { if (mine === accepting.seq) { accepting.quoting = false; paint(); } });
    }
    panel.addEventListener('change', function (e) {
      panel.querySelector('[data-qt-accept-err]').hidden = true;
      if (e.target.name === 'qt-delivery' || e.target.name === 'region') quoteShipping(); else paint();
    });
    // Only the methods the store has on; the first one is chosen for you.
    call('get_public_checkout_capabilities', { p_tenant_id: tenant }).then(function (caps) {
      var on = {};
      ((caps && caps.methods) || []).forEach(function (m) { on[m.code] = m.available === true; });
      var first = null;
      panel.querySelectorAll('[name=qt-pay]').forEach(function (input) {
        input.disabled = !on[input.value];
        if (on[input.value] && !first) first = input;
      });
      if (first && !pay()) first.checked = true;
      if (!first) {
        var bad = panel.querySelector('[data-qt-accept-err]');
        bad.textContent = 'Por ahora no podemos recibir pagos en línea. Escríbenos y lo coordinamos.'; bad.hidden = false;
      }
      paint();
    }).catch(function () { paint(); });
    // The account's saved address, if there is one.
    if (account && account.session) {
      fetch(sbUrl + '/rest/v1/customer_addresses?select=street_address,street_number,apartment,comuna,city,region&customer_id=eq.' +
        encodeURIComponent(account.row.id) + '&order=is_default.desc,created_at.desc&limit=1', {
        headers: { apikey: sbKey, authorization: 'Bearer ' + account.session.access_token, accept: 'application/json' }
      }).then(function (r) { return r.ok ? r.json() : []; }).then(function (rows) {
        var a = rows && rows[0]; if (!a || field('line1').value) return;
        field('line1').value = [a.street_address, a.street_number].filter(Boolean).join(' ');
        field('line2').value = a.apartment || '';
        field('city').value = a.comuna || a.city || '';
        var region = text(a.region).toLowerCase();
        REGIONS.forEach(function (r) { if (region && region.indexOf(r.toLowerCase()) >= 0) field('region').value = r; });
      }).catch(function () {});
    }
    paint();
  }

  function acceptOrder() {
    var panel = $('[data-qt-accept]'), o = current.data.offer; if (!panel || !accepting) return;
    var bad = panel.querySelector('[data-qt-accept-err]');
    function field(n) { return text((panel.querySelector('[name=' + n + ']') || {}).value); }
    var deliveryEl = panel.querySelector('[name=qt-delivery]:checked'), payEl = panel.querySelector('[name=qt-pay]:checked');
    var delivery = deliveryEl ? deliveryEl.value : 'pickup', method = payEl ? payEl.value : '';
    var body = { operation_key: accepting.key, offer_id: o.id, delivery_type: delivery, payment_method: method,
      shipping_quote_cost: delivery === 'shipping' && accepting.ship ? accepting.ship.gross : 0 };
    if (delivery === 'shipping') {
      if (!field('line1') || !field('city') || !field('region')) { bad.textContent = 'Completa la dirección, la comuna y la región.'; bad.hidden = false; return; }
      body.shipping_address_line1 = field('line1'); body.shipping_address_line2 = field('line2') || null;
      body.shipping_city = field('city'); body.shipping_state = field('region');
    }
    accepting.sending = true;
    var btn = panel.querySelector('[data-act=send-accept]');
    btn.disabled = true; btn.textContent = 'Creando tu pedido…';
    call('accept_public_customer_quote_v1', { p_token: current.token, p_request: body })
      .then(function (receipt) { return goToOrder(receipt); })
      .catch(function (err) {
        accepting.sending = false;
        var code = (err.data && err.data.message) || '', detail = (err.data && err.data.details) || '';
        bad.textContent = code === 'quote_stock_changed' ? '«' + detail + '» se acabó recién. Pídenos una oferta nueva con «Pedir cambios».'
          : /^Shipping quote changed/.test(code) ? 'El costo del despacho cambió: revisa el total y vuelve a aceptar.'
          : code === 'quote_offer_expired' ? 'La oferta venció. Pídenos una nueva con «Pedir cambios».'
          : code === 'quote_payment_unavailable' ? 'Ese medio de pago no está disponible ahora. Elige otro.'
          : code === 'quote_not_open' || code === 'quote_offer_outdated' ? 'La cotización cambió. Recarga para ver la de ahora.'
          : 'No pudimos crear el pedido. Revisa tu conexión e inténtalo de nuevo.';
        bad.hidden = false;
        btn.disabled = false; btn.textContent = 'Aceptar y pagar';
      });
  }

  // The order's own page has its payment: Mercado Pago opens from here, a
  // transfer shows its details there.
  function goToOrder(receipt) {
    try { if (R) R.saveOrderAccess({ order_id: receipt.order_id, access_token: receipt.access_token, expires_at: receipt.expires_at, replay: receipt.replay === true }); } catch (e) { /* the order page asks for the link again */ }
    var orderUrl = d.orderUrl + encodeURIComponent(receipt.order_id);
    if (receipt.payment_method !== 'mercadopago' || receipt.payment_status === 'paid') { location.assign(orderUrl); return null; }
    return fetch(sbUrl + '/functions/v1/mercadopago-create-preference', {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + sbKey, 'content-type': 'application/json' },
      body: JSON.stringify({ order_id: receipt.order_id, order_access_token: receipt.access_token })
    }).then(function (r) { return r.ok ? r.json() : null; }).then(function (pref) {
      location.assign(pref && typeof pref.init_point === 'string' && pref.init_point ? pref.init_point : orderUrl);
    }).catch(function () { location.assign(orderUrl); });
  }

  var ORDER_STATE = {
    ready_for_pickup: 'Listo para retiro en el taller.', delivered: 'Entregado.', cancelled: 'Este pedido se anuló.'
  };
  function orderBlock(order, acts) {
    var pending = order.paymentStatus !== 'paid' && order.status !== 'cancelled';
    var state = pending ? (order.waiting ? 'Falta el pago. Con él apartamos lo que hay y pedimos lo que viene a pedido.' : 'Falta el pago para prepararlo.')
      : ORDER_STATE[order.status] || (order.status === 'shipped'
        ? 'Va en camino' + (order.trackingCarrier ? ' por ' + order.trackingCarrier : '') + (order.trackingNumber ? ', código ' + order.trackingNumber : '') + '.'
        : order.waiting ? 'Pagado. Estamos esperando lo que viene a pedido y te avisamos cuando llegue.' : 'Pagado. Lo estamos preparando.');
    var lines = (order.lines || []).map(function (l) {
      var tag = !l.onOrder ? '<span class="qt-tag" data-kind="in_stock">Apartado para ti</span>'
        : l.arrived ? '<span class="qt-tag" data-kind="in_stock">Llegó</span>'
        : '<span class="qt-tag" data-kind="on_order">A pedido' + (l.leadDaysMin != null ? ' · ' + leadText(l.leadDaysMin, l.leadDaysMax) : '') + '</span>';
      return '<li><span>' + esc(l.name) + (l.quantity > 1 ? ' · ' + l.quantity : '') + '</span>' + tag + '</li>';
    }).join('');
    return '<div class="qt-card qt-order"><h2 class="qt-h2">Tu pedido ' + esc(order.number) + '</h2>' +
      '<p class="qt-order-state">' + esc(state) + '</p>' +
      (order.status === 'cancelled' ? '' : '<ul class="qt-order-lines">' + lines + '</ul>') +
      '<div class="qt-totals"><div><span>' + (order.deliveryType === 'shipping' ? 'Despacho' : 'Retiro en el taller') + '</span><span>' +
        (order.deliveryType === 'shipping' ? money(order.shippingCost) : 'Sin costo') + '</span></div>' +
        '<div class="total"><span>Total</span><span>' + money(order.total) + '</span></div></div>' +
      (acts.openOrder ? '<div class="qt-acts"><button class="qt-btn ' + (pending ? 'fill' : 'line') + '" data-act="open-order">' + (pending ? 'Pagar el pedido' : 'Ver el pedido') + '</button></div>' : '') +
      '</div>';
  }
  function openOrder(btn) {
    btn.disabled = true;
    call('open_public_customer_quote_order_v1', { p_token: current.token })
      .then(function (receipt) { return goToOrder(receipt); })
      .catch(function () { btn.disabled = false; toast('No pudimos abrir el pedido. Revisa tu conexión.', true); });
  }

  function openQuote(token, fresh) {
    current = { token: token, data: null, mode: 'view' };
    show('loading');
    return call('get_public_customer_quote_v1', { p_token: token }).then(function (data) {
      if (!data) {
        var sent = load(SENT, []).filter(function (s) { return s && s.t !== token; });
        save(SENT, sent);
        toast('Este enlace ya no sirve. Pídenos uno nuevo.', true);
        return start(true);
      }
      current.data = data;
      drawQuote();
      if (fresh) toast('Recibimos tu cotización ' + (data.quote && data.quote.number) + '.');
      window.scrollTo(0, 0);
    }).catch(function () { toast('No pudimos abrir la cotización. Revisa tu conexión.', true); show('build'); });
  }

  function respond(action, extra) {
    var o = current.data.offer || {};
    var body = { action: action, operation_key: uuid(), offer_id: o.id };
    for (var k in extra) body[k] = extra[k];
    return call('respond_public_customer_quote_v1', { p_token: current.token, p_response: body })
      .then(function () { return openQuote(current.token, false); })
      .then(function () {
        toast(action === 'reject' ? 'Listo, quedó rechazada.' : 'Recibimos tus cambios. Te enviamos una oferta nueva.');
      })
      .catch(function (err) {
        var code = (err.data && err.data.message) || '';
        toast(code === 'quote_offer_expired' ? 'La oferta venció. Escríbenos y la renovamos.'
          : code === 'quote_offer_outdated' || code === 'quote_not_open' ? 'La cotización cambió. Mira la versión de ahora.'
          : 'No se pudo enviar. Revisa tu conexión.', true);
        return openQuote(current.token, false);
      });
  }

  // The server draws the offer with the quote's link, sent in the body.
  function offerPdf(btn) {
    if (btn.disabled || !current.token) return;
    var before = btn.textContent;
    btn.disabled = true; btn.textContent = 'Preparando…';
    fetch(d.pdfUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ access_token: current.token })
    }).then(function (r) {
      if (!r.ok) throw new Error('http ' + r.status);
      return r.blob();
    }).then(function (blob) {
      var number = (current.data && current.data.quote && current.data.quote.number) || 'oferta';
      var url = URL.createObjectURL(blob), a = document.createElement('a');
      a.href = url;
      a.download = 'cotizacion_' + String(number).replace(/[^0-9A-Za-z-]/g, '_') + '.pdf';
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
    }).catch(function () {
      toast('No pudimos preparar el PDF. Inténtalo de nuevo.', true);
    }).then(function () { btn.disabled = false; btn.textContent = before; });
  }

  $('[data-qt-view]').addEventListener('click', function (e) {
    var open = e.target.closest('[data-open]');
    if (open) { e.preventDefault(); openQuote(open.dataset.open, false); return; }
    var btn = e.target.closest('[data-act]'); if (!btn) return;
    var act = btn.dataset.act;
    if (act === 'builder') { e.preventDefault(); refreshBuilder(); return; }
    if (act === 'pdf') { offerPdf(btn); return; }
    if (act === 'copy') {
      var url = location.origin + location.pathname + '#t=' + encodeURIComponent(current.token);
      var done = function () { toast('Enlace copiado.'); };
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(done, function () { prompt('Copia tu enlace', url); });
      else prompt('Copia tu enlace', url);
      return;
    }
    if (act === 'accept' || act === 'change' || act === 'reject' || act === 'notify') { current.mode = act; drawQuote(); return; }
    if (act === 'save-notify') {
      var byEmail = !!(root.querySelector('[data-notify=email]:checked'));
      var byWhatsapp = !!(root.querySelector('[data-notify=whatsapp]:checked'));
      if (!byEmail && !byWhatsapp) { toast('Elige al menos uno.', true); return; }
      btn.disabled = true;
      call('update_public_customer_quote_notify_v1', { p_token: current.token, p_notify: { notify_email: byEmail, notify_whatsapp: byWhatsapp } })
        .then(function () {
          save(NOTIFY, { e: byEmail, w: byWhatsapp });
          return openQuote(current.token, false);
        })
        .then(function () { toast('Listo: te avisamos por ' + notices({ notifyEmail: byEmail, notifyWhatsapp: byWhatsapp }) + '.'); })
        .catch(function (err) {
          var code = (err.data && err.data.message) || '';
          toast(code === 'quote_contact_invalid' ? 'Tu cuenta no tiene ese dato. Agrégalo en tu cuenta.'
            : code === 'quote_not_open' ? 'Esta cotización ya no recibe avisos.'
            : 'No se pudo guardar. Revisa tu conexión.', true);
          return openQuote(current.token, false);
        });
      return;
    }
    if (act === 'cancel-change') { current.mode = 'view'; drawQuote(); return; }
    if (act === 'send-accept') { acceptOrder(); return; }
    if (act === 'open-order') { openOrder(btn); return; }
    btn.disabled = true;
    if (act === 'send-reject') respond('reject', { note: text(($('[data-reject-note]') || {}).value) || null });
    if (act === 'send-change') {
      var changes = [];
      root.querySelectorAll('[data-line]').forEach(function (input) {
        var n = Math.max(0, Math.min(99, parseInt(input.value, 10) || 0));
        changes.push({ line_no: Number(input.dataset.line), quantity: n });
      });
      var note = text(($('[data-change-note]') || {}).value);
      respond('request_changes', { lines: changes, note: note || null });
    }
  });

  // ---- where the page starts -------------------------------------------------
  function start(skipHash) {
    var hash = skipHash ? '' : location.hash.replace(/^#/, '');
    var params = new URLSearchParams(hash);
    var token = params.get('t');
    if (token) {
      // The link stays only in this browser's list, never in the address bar.
      history.replaceState(null, '', location.pathname + location.search);
      if (!load(SENT, []).some(function (s) { return s && s.t === token; })) remember('', token);
      return openQuote(token, false);
    }
    // From «Mi cuenta»: the session asks for a fresh link to its own quote.
    var mine = params.get('q');
    if (mine) {
      history.replaceState(null, '', location.pathname + location.search);
      show('loading');
      return loadAccount(false).then(function (a) {
        account = a; drawBox();
        if (!a) {
          try { sessionStorage.setItem(AFTER, location.pathname + '#q=' + encodeURIComponent(mine)); } catch (e) { /* the account opens instead */ }
          location.assign(d.loginUrl);
          return;
        }
        return call('open_my_customer_quote_v1', { p_tenant_id: tenant, p_quote_id: mine }, a.session.access_token).then(function (r) {
          remember(r.quote_number, r.access_token);
          return openQuote(r.access_token, false);
        });
      }).catch(function () { toast('No pudimos abrir esa cotización.', true); return start(true); });
    }
    if (lines.length) return refreshBuilder();
    var latest = load(SENT, [])[0];
    if (latest && latest.t) return openQuote(latest.t, false);
    show('empty');
    return Promise.resolve();
  }
  window.addEventListener('hashchange', function () { start(false); });
  start(false);
  refreshAccount();
})();
''';

/// The product page's «Agregar a la cotización»: the quantity of the product
/// goes into the quote this browser keeps, and the note under the button
/// says how many products it has, with the way to it.
const quoteAddScript = r'''
(function () {
  var section = document.querySelector('[data-product-id]');
  if (!section) return;
  var KEY = 'vinabike.quote.lines';
  function load() { try { return JSON.parse(localStorage.getItem(KEY) || '[]') || []; } catch (e) { return []; } }
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('[data-quote-add]'); if (!btn) return;
    e.preventDefault();
    var id = section.dataset.productId;
    var scope = btn.closest('.buy') || document;
    var input = scope.querySelector('[data-quote-qty]') || scope.querySelector('input[name=cantidad]');
    var q = Math.max(1, Math.min(99, parseInt(input && input.value, 10) || 1));
    var lines = load().filter(function (l) { return l && l.id; });
    var found = lines.filter(function (l) { return l.id === id; })[0];
    if (found) found.q = Math.min(99, found.q + q); else lines.push({ id: id, q: q });
    try { localStorage.setItem(KEY, JSON.stringify(lines)); } catch (err) {}
    var note = document.querySelector('[data-quote-note]');
    if (note) {
      note.querySelector('[data-quote-note-text]').textContent = 'Agregado a tu cotización · ' + lines.length + (lines.length === 1 ? ' producto' : ' productos');
      note.hidden = false;
    }
  });
  document.addEventListener('click', function (e) {
    var step = e.target.closest('[data-quote-step]'); if (!step) return;
    var input = step.parentNode.querySelector('[data-quote-qty]'); if (!input) return;
    input.value = Math.max(1, Math.min(99, (parseInt(input.value, 10) || 1) + Number(step.dataset.quoteStep)));
  });
})();
''';
