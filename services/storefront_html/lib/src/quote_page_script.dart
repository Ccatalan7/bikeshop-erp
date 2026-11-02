/// What `/cotizacion` does in the browser. The lines the visitor gathers live
/// in `localStorage` (`vinabike.quote.lines`, `[{id, q}]`) like the cart; a
/// sent quote is remembered by its number and its link (`vinabike.quote.sent`)
/// so «Tu cotización» opens it again. Every state comes from the database's
/// public commands (20261102041700): `request_public_customer_quote_v1`,
/// `get_public_customer_quote_v1`, `respond_public_customer_quote_v1` and
/// `get_public_on_order_terms_v1`. Opening the link only reads; accepting,
/// changing or rejecting is always a click on this page, so a mail scanner
/// that follows the link answers nothing.
const quotePageScript = r'''
(function () {
  var root = document.querySelector('[data-qt]');
  if (!root) return;
  var tenant = root.dataset.tenant, sbUrl = root.dataset.sbUrl, sbKey = root.dataset.sbKey;
  var LINES = 'vinabike.quote.lines', SENT = 'vinabike.quote.sent';
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
  function call(fn, body) {
    return fetch(sbUrl + '/rest/v1/rpc/' + fn, {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + sbKey, 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify(body)
    }).then(function (r) {
      return r.text().then(function (t) {
        var data = null;
        try { data = t ? JSON.parse(t) : null; } catch (e) { data = null; }
        if (!r.ok) { var err = new Error((data && data.message) || ('http ' + r.status)); err.data = data || {}; throw err; }
        return data;
      });
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
  function channel() { var c = form.querySelector('input[name=channel]:checked'); return c ? c.value : 'whatsapp'; }
  function syncChannel() {
    $('[data-qt-phone] span').textContent = channel() === 'whatsapp' ? 'Teléfono (WhatsApp)' : 'Teléfono (opcional)';
    $('[data-qt-email] span').textContent = channel() === 'email' ? 'Correo' : 'Correo (opcional)';
  }
  form.addEventListener('change', syncChannel); syncChannel();
  function fail(field, message) {
    var err = $('[data-qt-err]'); err.textContent = message; err.hidden = false;
    form.querySelectorAll('[data-bad]').forEach(function (el) { el.removeAttribute('data-bad'); });
    var input = field ? form.querySelector('[name=' + field + ']') : null;
    if (input) { input.closest('.qt-field').setAttribute('data-bad', ''); input.focus(); }
  }
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (sending) return;
    var f = form.elements;
    var name = text(f['name'].value), email = text(f['email'].value), phone = text(f['phone'].value);
    var digits = phone.replace(/[^0-9]/g, '');
    if (name.length < 2) return fail('name', 'Escribe tu nombre.');
    if (channel() === 'whatsapp' && digits.length < 8) return fail('phone', 'Escribe tu teléfono con WhatsApp.');
    if (channel() === 'email' && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return fail('email', 'Escribe un correo válido.');
    if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return fail('email', 'Revisa el correo.');
    if (!lines.length) return fail(null, 'Agrega al menos un producto.');
    $('[data-qt-err]').hidden = true;
    sending = true;
    var button = $('[data-qt-send]'); button.disabled = true; button.textContent = 'Enviando…';
    // One key per sending: a retry after a dropped connection is the same quote.
    var key = form.dataset.key || (form.dataset.key = uuid());
    call('request_public_customer_quote_v1', {
      p_tenant_id: tenant,
      p_request: {
        request_idempotency_key: key, customer_name: name, customer_email: email || null,
        customer_phone: phone || null, preferred_channel: channel(), customer_notes: text(f['notes'].value) || null,
        items: lines.map(function (l) { return { product_id: l.id, quantity: l.q }; })
      }
    }).then(function (receipt) {
      var sent = load(SENT, []).filter(function (s) { return s && s.n !== receipt.quote_number; });
      sent.unshift({ n: receipt.quote_number, t: receipt.access_token, at: new Date().toISOString() });
      save(SENT, sent.slice(0, 10));
      lines = []; persist(); delete form.dataset.key;
      openQuote(receipt.access_token, true);
    }).catch(function (err) {
      var code = (err.data && err.data.message) || '';
      var detail = (err.data && err.data.details) || '';
      if (code === 'quote_contact_invalid') {
        var field = { customer_name: 'name', customer_email: 'email', customer_phone: 'phone' }[detail] || null;
        fail(field, field === 'phone' ? 'Revisa el teléfono.' : field === 'email' ? 'Revisa el correo.' : 'Revisa tus datos.');
      } else if (code === 'quote_product_not_available') {
        fail(null, 'Un producto ya no está disponible en el sitio. Actualizamos la lista.');
        refreshBuilder();
      } else if (code === 'quote_rate_limited') {
        fail(null, 'Recibimos varias cotizaciones tuyas hoy. Escríbenos si necesitas otra.');
      } else {
        fail(null, 'No se pudo enviar. Revisa tu conexión e inténtalo de nuevo.');
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
    changes_requested: 'Pediste cambios', rejected: 'Rechazaste la oferta', expired: 'La oferta venció', cancelled: 'La cotización se anuló'
  };
  var current = { token: null, data: null, mode: 'view' };

  function lineCell(l) {
    var lead = l.availability === 'on_order' && l.leadDaysMin != null
      ? ' · llega en ' + (l.leadDaysMin === l.leadDaysMax ? l.leadDaysMin : l.leadDaysMin + ' a ' + l.leadDaysMax) + ' días hábiles' : '';
    var partial = l.quantity > 0 && l.quantity < l.quantityRequested ? ' · ' + l.quantity + ' de ' + l.quantityRequested : '';
    return '<strong>' + esc(l.name) + '</strong>' +
      '<br><span class="qt-tag" data-kind="' + esc(l.availability) + '">' + esc((AVAIL[l.availability] || '') + partial + lead) + '</span>' +
      (l.note ? '<p class="qt-note">' + esc(l.note) + '</p>' : '');
  }

  function drawQuote() {
    var d = current.data, q = d.quote || {}, o = d.offer, acts = d.actions || {};
    var view = $('[data-qt-view]');
    var html = '<p class="qt-kick">Cotización ' + esc(q.number) + '</p>' +
      '<h1 class="qt-title">' + (q.status === 'offered' ? 'Tu oferta está lista' : q.status === 'accepted' ? 'Oferta aceptada' : q.status === 'confirming' ? 'Estamos confirmando tu cotización' : esc(STATUS[q.status] || 'Tu cotización')) + '</h1>' +
      '<div class="qt-status"><span class="qt-pill" data-s="' + esc(q.status) + '">' + esc(STATUS[q.status] || q.status) + '</span>' +
      (q.status === 'offered' && q.expiresAt ? '<span class="qt-when">Vale hasta el ' + esc(when(q.expiresAt)) + '</span>' : '') +
      (q.status === 'confirming' ? '<span class="qt-when">Te avisamos por ' + (q.preferredChannel === 'email' ? 'correo' : 'WhatsApp') + ' cuando esté lista.</span>' : '') + '</div>';

    if (o && o.lines) {
      var changing = current.mode === 'change';
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
      if (acts.accept && !changing) {
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
      if (current.mode === 'reject') {
        html += '<label class="qt-field" style="margin-top:18px"><span>¿Nos cuentas por qué? <i>(opcional)</i></span><textarea rows="2" maxlength="2000" data-reject-note></textarea></label>' +
          '<div class="qt-acts"><button class="qt-btn fill" data-act="send-reject">Rechazar oferta</button><button class="qt-btn text" data-act="cancel-change">Volver</button></div>';
      }
      if (current.mode === 'accept') {
        html += '<div class="qt-acts"><button class="qt-btn fill" data-act="send-accept">Confirmar · ' + money(o.total) + '</button><button class="qt-btn text" data-act="cancel-change">Volver</button></div>';
      }
      html += '</div>';
    } else {
      html += '<div class="qt-card"><table class="qt-offer"><thead><tr><th>Lo que pediste</th><th></th><th class="num">Cant.</th></tr></thead><tbody>' +
        (d.requested || []).map(function (l) {
          return '<tr><td><strong>' + esc(l.name) + '</strong>' + (l.sku ? '<p class="qt-note">SKU ' + esc(l.sku) + '</p>' : '') + '</td><td></td><td class="num">' + l.quantity + '</td></tr>';
        }).join('') + '</tbody></table></div>';
    }

    if (q.status === 'accepted') {
      html += '<div class="qt-card"><h2 class="qt-h2">Lo que sigue</h2><p class="qt-note">Te escribimos por ' + (q.preferredChannel === 'email' ? 'correo' : 'WhatsApp') + ' para coordinar el pago y la entrega.</p></div>';
    }
    var history = d.history || [];
    if (history.length) {
      html += '<div class="qt-card"><h2 class="qt-h2">Historia</h2><ul class="qt-history">' +
        history.slice().reverse().map(function (h) { return '<li><span>' + esc(HISTORY[h.type] || h.type) + '</span><time>' + esc(when(h.at)) + '</time></li>'; }).join('') + '</ul></div>';
    }
    html += '<p class="qt-link">Con este enlace vuelves a tu cotización desde cualquier equipo. <button class="qt-btn text" data-act="copy">Copiar enlace</button></p>';
    var others = load(SENT, []).filter(function (s) { return s && s.t !== current.token; });
    if (others.length) {
      html += '<p class="qt-others">Otras cotizaciones: ' + others.map(function (s) { return '<a href="#t=' + encodeURIComponent(s.t) + '" data-open="' + esc(s.t) + '">' + esc(s.n) + '</a>'; }).join(' · ') + '</p>';
    }
    if (lines.length) html += '<p class="qt-others"><a href="#" data-act="builder">Ver la cotización que estás armando (' + lines.length + ')</a></p>';
    view.innerHTML = html;
    show('view');
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
        toast(action === 'accept' ? 'Oferta aceptada. Te escribimos para el pago y la entrega.' : action === 'reject' ? 'Listo, quedó rechazada.' : 'Recibimos tus cambios. Te enviamos una oferta nueva.');
      })
      .catch(function (err) {
        var code = (err.data && err.data.message) || '';
        toast(code === 'quote_offer_expired' ? 'La oferta venció. Escríbenos y la renovamos.'
          : code === 'quote_offer_outdated' || code === 'quote_not_open' ? 'La cotización cambió. Mira la versión de ahora.'
          : 'No se pudo enviar. Revisa tu conexión.', true);
        return openQuote(current.token, false);
      });
  }

  $('[data-qt-view]').addEventListener('click', function (e) {
    var open = e.target.closest('[data-open]');
    if (open) { e.preventDefault(); openQuote(open.dataset.open, false); return; }
    var btn = e.target.closest('[data-act]'); if (!btn) return;
    var act = btn.dataset.act;
    if (act === 'builder') { e.preventDefault(); refreshBuilder(); return; }
    if (act === 'copy') {
      var url = location.origin + location.pathname + '#t=' + encodeURIComponent(current.token);
      var done = function () { toast('Enlace copiado.'); };
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(done, function () { prompt('Copia tu enlace', url); });
      else prompt('Copia tu enlace', url);
      return;
    }
    if (act === 'accept' || act === 'change' || act === 'reject') { current.mode = act; drawQuote(); return; }
    if (act === 'cancel-change') { current.mode = 'view'; drawQuote(); return; }
    btn.disabled = true;
    if (act === 'send-accept') respond('accept', {});
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
    var token = new URLSearchParams(hash).get('t');
    if (token) {
      // The link stays only in this browser's list, never in the address bar.
      history.replaceState(null, '', location.pathname + location.search);
      var sent = load(SENT, []);
      if (!sent.some(function (s) { return s && s.t === token; })) {
        sent.unshift({ n: '', t: token, at: new Date().toISOString() });
        save(SENT, sent.slice(0, 10));
      }
      return openQuote(token, false);
    }
    if (lines.length) return refreshBuilder();
    var latest = load(SENT, [])[0];
    if (latest && latest.t) return openQuote(latest.t, false);
    show('empty');
    return Promise.resolve();
  }
  window.addEventListener('hashchange', function () { start(false); });
  start(false);
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
