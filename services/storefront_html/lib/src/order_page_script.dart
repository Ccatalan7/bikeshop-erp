/// The order page's behavior, as Flutter's `OrderConfirmationPage`: find
/// the order's access in this tab (the checkout's receipt wins over a saved
/// one), settle the cart's one-time subtraction, close a transfer's
/// attempt, verify Mercado Pago's return (`mercadopago-get-payment`) before
/// trusting it, read the order with `get_public_online_order_by_access_token`
/// and draw it with the same words for each payment state
/// (`OrderConfirmationPolicy`). Purchases are measured once per load, like
/// Flutter, and GA4 and Meta discard a repeated order id.
const orderPageScript = r'''
(function () {
  var root = document.querySelector('[data-od]');
  if (!root) return;
  var tenant = root.dataset.tenant, orderId = root.dataset.order;
  var sbUrl = root.dataset.sbUrl, sbKey = root.dataset.sbKey;
  var cart = window.vinabikeCart;
  var R = window.vinabikeCheckoutRecords(tenant, cart);
  function $(sel) { return root.querySelector(sel); }
  function text(v) { return v == null ? '' : String(v).trim(); }
  function esc(v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
  // ChileanUtils.formatCurrency: «$ 89.000», «-$ 1.500», half away from zero.
  function money(v) {
    var n = Number(v) || 0, whole = Math.round(Math.abs(n)) * (n < 0 ? -1 : 1);
    if (whole === 0) return '$ 0';
    var digits = String(Math.abs(whole)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    return (whole < 0 ? '-$ ' : '$ ') + digits;
  }

  // ---- what Mercado Pago's return says (`_observeCallback`) --------------
  var query = new URLSearchParams(location.search);
  var rawStatus = text(query.get('status')).toLowerCase() || null;
  var statusGroup = { success: 'approved', approved: 'approved', pending: 'pending', in_process: 'pending',
    failure: 'failure', failed: 'failure', rejected: 'failure' }[rawStatus] || null;
  var paymentId = text(query.get('payment_id') || query.get('collection_id'));

  // ---- Supabase --------------------------------------------------------
  function call(path, body) {
    return fetch(sbUrl + path, {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + sbKey, 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify(body)
    }).then(function (r) {
      return r.text().then(function (t) {
        var data = null;
        try { data = t ? JSON.parse(t) : null; } catch (e) { data = null; }
        if (!r.ok) { var err = new Error('http ' + r.status); err.status = r.status; throw err; }
        return data;
      });
    });
  }

  // ---- states ------------------------------------------------------------
  var toastTimer = null;
  function toast(message, bad, seconds) {
    var el = $('[data-od-toast]');
    el.textContent = message;
    el.classList.toggle('bad', !!bad);
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, (seconds || 4) * 1000);
  }
  function show(state) {
    $('[data-od-loading]').hidden = state !== 'loading';
    $('[data-od-state]').hidden = state !== 'state';
    $('[data-od-full]').hidden = state !== 'full';
    root.setAttribute('data-od-ready', state);
  }
  // _buildError / _buildNotFound
  function stateView(kind, message) {
    var box = $('[data-od-state]');
    box.classList.toggle('err', kind === 'error');
    $('[data-od-state-icon]').innerHTML = root.getAttribute(kind === 'error' ? 'data-icon-failed' : 'data-icon-bag');
    $('[data-od-state-title]').textContent = kind === 'error' ? 'No pudimos cargar tu pedido' : 'Pedido no encontrado';
    $('[data-od-state-text]').textContent = message;
    show('state');
  }
  function warn(on) { $('[data-od-warn]').hidden = !on; }

  // ---- OrderConfirmationPolicy.resolve --------------------------------------
  function presentation(order) {
    var payment = text(order.paymentStatus).toLowerCase(), method = text(order.paymentMethod).toLowerCase();
    if (text(order.status).toLowerCase() === 'cancelled') return 'cancelled';
    if (payment === 'paid' || order.paidAt) return 'paid';
    if (rawStatus === 'failure' || rawStatus === 'rejected' || payment === 'failed' || payment === 'refunded') return 'failed';
    if (rawStatus === 'pending' || rawStatus === 'in_process' || (method === 'mercadopago' && payment === 'pending')) return 'pending';
    if (['transfer', 'transferencia', 'bank_transfer'].indexOf(method) >= 0) return 'transferPending';
    return 'orderReceived';
  }
  var WORDS = {
    cancelled: { tone: 'cancelled', icon: 'block', status: 'blocked', kicker: 'PEDIDO CANCELADO',
      title: 'Este pedido fue cancelado.',
      sub: 'No realices ni reintentes un pago para este pedido. Los montos quedan visibles solo como registro de lo solicitado.',
      line: 'El pedido está cerrado. No se preparará ni debe pagarse.', pill: 'PEDIDO CANCELADO',
      foot: 'Este pedido está cerrado. Conserva el número solo como referencia y no realices un pago.',
      steps: ['No realices ni reintentes el pago de este pedido.',
        'Si ya habías pagado, contáctanos con el número de pedido para revisar el estado del reembolso.',
        'Si todavía quieres los productos, inicia un pedido nuevo.'] },
    paid: { tone: 'paid', icon: 'check', status: 'ok', kicker: 'PAGO CONFIRMADO',
      title: 'Pago confirmado. Estamos preparando tu pedido.',
      sub: 'Recibimos tu pago y dejaremos el pedido listo para retiro o despacho.',
      line: null, pill: 'PAGO PROCESADO',
      foot: 'Guarda tu número de pedido y revisa tu correo para seguir el estado de la compra.',
      steps: ['Te enviaremos un email de confirmación con los detalles de tu pedido.',
        'Procesaremos tu pedido en 1-2 días hábiles.', 'Te contactaremos si necesitamos más información.'] },
    failed: { tone: 'failed', icon: 'close', status: 'error', kicker: 'PAGO NO COMPLETADO',
      title: 'El pago no se completó.',
      sub: 'Tu pedido quedó guardado, pero no será preparado hasta que completes el pago. Puedes reintentar Mercado Pago desde el resumen.',
      line: 'El pago no se completó. Puedes intentar nuevamente.', pill: 'PAGO FALLIDO',
      foot: 'Tu pedido está guardado, pero debes completar el pago para que podamos prepararlo.',
      steps: ['Reintenta el pago desde el resumen del pedido.',
        'Si Mercado Pago vuelve a rechazarlo, prueba con otro medio de pago.',
        'Te podemos ayudar si nos escribes con tu número de pedido.'] },
    pending: { tone: 'pending', icon: 'schedule', status: 'info', kicker: 'PAGO EN REVISIÓN',
      title: 'Estamos confirmando tu pago.',
      sub: 'Mercado Pago todavía está revisando la operación. Evita pagar de nuevo mientras el estado siga pendiente.',
      line: 'El pago sigue pendiente de confirmación en Mercado Pago.', pill: 'PAGO EN REVISIÓN',
      foot: 'Guarda tu número de pedido. Te avisaremos cuando Mercado Pago confirme el resultado.',
      steps: ['Mercado Pago está revisando el pago.', 'No vuelvas a pagar mientras el estado siga pendiente.',
        'Te notificaremos apenas se confirme o si necesitamos otro medio de pago.'] },
    transferPending: { tone: 'transfer', icon: 'bank', status: 'info', kicker: 'PAGO POR CONFIRMAR',
      title: 'Pedido recibido. Falta confirmar el pago.',
      sub: 'Realiza la transferencia con los datos indicados y envía el comprobante para que podamos preparar el pedido.',
      line: 'Esperamos el comprobante de transferencia para confirmar el pago.', pill: 'ESPERANDO TRANSFERENCIA',
      foot: 'Guarda tu número de pedido y envía el comprobante para confirmar la compra.',
      steps: ['Realiza la transferencia por el total indicado.', 'Envía el comprobante con tu número de pedido.',
        'Prepararemos el pedido cuando el pago quede confirmado.'] },
    orderReceived: { tone: 'paid', icon: 'check', status: 'ok', kicker: 'PEDIDO RECIBIDO',
      title: 'Pedido recibido.',
      sub: 'Recibimos el pedido y te avisaremos apenas el equipo lo prepare para retiro o despacho.',
      line: null, pill: 'PAGO POR CONFIRMAR',
      foot: 'Guarda tu número de pedido y revisa tu correo para seguir el estado del pedido.',
      steps: ['Te enviaremos un email de confirmación con los detalles de tu pedido.',
        'Procesaremos tu pedido en 1-2 días hábiles.', 'Te contactaremos si necesitamos más información.'] }
  };
  var ACCENT = { cancelled: '#b45309', paid: '#10b981', failed: '#dc2626', pending: '#f59e0b', transfer: '#093357' };
  // _formatPaymentMethod
  function methodLabel(method) {
    var m = text(method).toLowerCase();
    if (m === 'cash_on_delivery') return 'POR DEFINIR';
    if (m === 'mercadopago') return 'MERCADOPAGO';
    if (m === 'transfer') return 'TRANSFERENCIA';
    return String(method || '').toUpperCase();
  }
  function deliveryLabel(type) { return type === 'pickup' ? 'Retiro en tienda' : type === 'shipping' ? 'Despacho' : String(type || ''); }
  // StorefrontTaxSummary's labels for the order's lines.
  function taxLabels(items) {
    var valid = true, taxable = false, exempt = false;
    items.forEach(function (it) {
      var q = Number(it.quantity), price = Number(it.unitPrice), rate = it.taxRate == null ? null : Number(it.taxRate);
      if (!(q >= 1) || !(price > 0) || price !== Math.round(price)) { valid = false; return; }
      if (rate === 0) exempt = true;
      else if (rate === 19 || (rate != null && Math.abs(rate - 0.19) < 1e-9)) taxable = true;
      else valid = false;
    });
    var mixed = taxable && exempt;
    return {
      valid: valid,
      net: mixed ? 'Neto + exento' : exempt && !taxable ? 'Subtotal exento' : 'Neto',
      iva: mixed ? 'IVA incluido (ítems afectos)' : taxable ? 'IVA incluido (19%)' : 'IVA'
    };
  }

  // ---- drawing (_buildConfirmation) -----------------------------------------
  var current = null, paymentMessage = null;
  function paint(order, items, storefront) {
    var state = presentation(order), w = WORDS[state];
    var hero = $('[data-od-hero]');
    hero.setAttribute('data-tone', w.tone);
    $('[data-od-kick-icon]').innerHTML = root.getAttribute('data-icon-' + w.icon);
    $('[data-od-kicker]').textContent = w.kicker;
    $('[data-od-title]').textContent = w.title;
    $('[data-od-sub]').textContent = w.sub;
    var name = text(storefront && storefront.schemaVersion === 1 && storefront.displayName) || 'Tienda';
    $('[data-od-store]').textContent = name.toUpperCase();
    $('[data-od-number]').textContent = order.number || 'N/A';
    $('[data-od-total]').textContent = money(order.total);
    $('[data-od-method]').textContent = methodLabel(order.paymentMethod);
    var line = state === 'cancelled' ? w.line : (paymentMessage || w.line);
    var status = $('[data-od-status]');
    status.hidden = !line;
    if (line) {
      $('[data-od-status-icon]').innerHTML = root.getAttribute('data-icon-' + w.status);
      $('[data-od-status-text]').textContent = line;
    }
    var details = [['Número de pedido', order.number || 'N/A'], ['Entrega', deliveryLabel(order.deliveryType || 'shipping')]];
    $('[data-od-details]').innerHTML = details.map(function (row) {
      return '<div class="od-row"><dt>' + esc(row[0].toUpperCase()) + '</dt><dd>' + esc(row[1]) + '</dd></div>';
    }).join('');
    $('[data-od-items]').innerHTML = items.map(function (it) {
      var sku = text(it.sku);
      return '<li class="od-item"><span class="od-item-text"><span class="od-item-name">' + esc(it.name || 'Producto') + '</span>' +
        (sku ? '<span class="od-item-sku">SKU: ' + esc(sku) + '</span>' : '') + '</span>' +
        '<span class="od-item-qty">x' + esc(it.quantity) + '</span><span class="od-item-price">' + esc(money(it.subtotal)) + '</span></li>';
    }).join('');
    var transfer = $('[data-od-transfer]');
    transfer.hidden = state !== 'transferPending';
    $('[data-od-amount]').textContent = money(order.total);
    $('[data-od-steps]').innerHTML = w.steps.map(function (s) { return '<li class="od-step">' + esc(s) + '</li>'; }).join('');
    // _buildSummaryRail
    $('[data-od-sum-title]').textContent = state === 'paid' ? 'RESUMEN DE COMPRA' : 'RESUMEN DEL PEDIDO';
    $('[data-od-sum-number]').textContent = order.number || 'N/A';
    $('[data-od-pill-method]').textContent = methodLabel(order.paymentMethod);
    var pill = $('[data-od-pill-state]');
    pill.textContent = w.pill;
    pill.style.setProperty('--o-tone', ACCENT[w.tone]);
    var tax = taxLabels(items), metrics = [[tax.valid ? tax.net : 'Neto', money(order.subtotal), false]];
    if (Number(order.taxAmount) > 0 || tax.valid) metrics.push([tax.valid ? tax.iva : 'IVA incluido', money(order.taxAmount), true]);
    if (Number(order.shippingCost) > 0) metrics.push(['Envío', money(order.shippingCost), true]);
    if (Number(order.discountAmount) > 0) metrics.push(['Descuento', money(-Number(order.discountAmount)), true]);
    $('[data-od-metrics]').innerHTML = metrics.map(function (m) {
      return '<div class="od-metric' + (m[2] ? ' sec' : '') + '"><span>' + esc(m[0]) + '</span><b>' + esc(m[1]) + '</b></div>';
    }).join('');
    $('[data-od-sum-total]').textContent = money(order.total);
    var retry = $('[data-act=retry]');
    retry.hidden = !(text(order.paymentMethod).toLowerCase() === 'mercadopago' && (state === 'failed' || state === 'pending'));
    $('[data-od-retry-label]').textContent = state === 'failed' ? 'PAGAR CON OTRO MEDIO' : 'REINTENTAR PAGO';
    $('[data-od-foot]').textContent = w.foot;
    current = { order: order, items: items, state: state };
    show('full');
  }

  // ---- measurement (_trackPurchaseIfEligible) -------------------------------
  function measurePurchase(order, items) {
    var payment = text(order.paymentStatus).toLowerCase();
    if (text(order.status).toLowerCase() === 'cancelled' || payment === 'failed' ||
        ['failure', 'failed', 'rejected'].indexOf(rawStatus) >= 0) return;
    var m = window.vinabikeMeasure;
    if (!m) return;
    var lines = items.map(function (it) {
      return { id: text(it.sku), name: it.name, price: Number(it.unitPrice) || 0, quantity: Number(it.quantity) || 0 };
    }).filter(function (it) { return it.id; });
    if (!lines.length) return;
    m.pixel('Purchase', {
      content_ids: lines.map(function (it) { return it.id; }), content_type: 'product',
      contents: lines.map(function (it) { return { id: it.id, quantity: it.quantity, item_price: it.price }; }),
      num_items: lines.reduce(function (n, it) { return n + it.quantity; }, 0), value: Number(order.total) || 0, currency: 'CLP'
    }, 'purchase_' + order.id);
    m.track('purchase', {
      transaction_id: order.id, currency: 'CLP', value: Number(order.total) || 0,
      items: lines.map(function (it) { return { item_id: it.id, item_name: it.name, price: it.price, quantity: it.quantity }; })
    });
  }

  // ---- the order (_loadOrder) -----------------------------------------------
  var token = null;
  function load(delayMs) {
    show('loading');
    return new Promise(function (done) { setTimeout(done, delayMs || 0); })
      .then(function () { return call('/rest/v1/rpc/get_public_online_order_by_access_token', { p_token: token }); })
      .then(function (envelope) {
        // onlineOrderFromPublicAccessResponse
        if (!envelope || typeof envelope !== 'object') throw new Error('Pedido no encontrado o acceso vencido');
        var order = envelope.order;
        if (!order || typeof order !== 'object') throw new Error('Respuesta pública de pedido inválida');
        if (String(order.id || '') !== orderId) throw new Error('El acceso no corresponde a este pedido');
        if (!isFinite(Date.parse(order.createdAt || ''))) throw new Error('Fechas públicas de pedido inválidas');
        var items = Array.isArray(envelope.items) ? envelope.items : [];
        paint(order, items, envelope.storefront);
        measurePurchase(order, items);
      })
      .catch(function () {
        // getPublicOrderById answers null on any failure: «not found».
        stateView('notFound', 'No pudimos encontrar este pedido.');
      });
  }

  // ---- the cart (_consumeCheckoutCartIfNeeded) --------------------------------
  function consumeCart() {
    return R.consumeCartOnce(orderId).then(function (outcome) {
      warn(R.showsWarning(outcome));
      if (cart && cart.badge) cart.badge();
      return outcome;
    });
  }

  // ---- Mercado Pago's return (_processCallback) -----------------------------
  var PENDING_MESSAGE = 'Estamos confirmando tu pago. Si ya fue aprobado, el pedido se actualizará en unos segundos.';
  function processCallback() {
    if (statusGroup === 'pending') return Promise.resolve('Tu pago está pendiente de confirmación. Te notificaremos cuando se procese.');
    if (statusGroup === 'failure') return Promise.resolve('El pago no se completó. Puedes intentar nuevamente.');
    if (!paymentId) return Promise.resolve('MercadoPago no devolvió un identificador de pago. Revisaremos el pedido y te contactaremos si el pago se acredita.');
    return call('/functions/v1/mercadopago-get-payment', { payment_id: paymentId, order_id: orderId, order_access_token: token })
      .catch(function () { return null; })
      .then(function (payment) {
        var status = text(payment && payment.status).toLowerCase(), paidOrder = text(payment && payment.order_id);
        if (status !== 'approved' || paidOrder !== orderId) return 'MercadoPago todavía no confirmó el pago. Te notificaremos cuando se procese.';
        return consumeCart().then(function () {
          // Only the provider's verification of this order retires its receipt.
          R.clearReceipt(orderId);
          return '¡Pago exitoso! Tu pedido está siendo procesado.';
        });
      });
  }

  // ---- entry (_initializeCurrentOrderRoute) -----------------------------------
  function start() {
    if (!tenant) { stateView('error', 'No pudimos identificar la tienda de este pedido.'); return; }
    var showWarning = false;
    Promise.resolve().then(function () {
      var access = R.readOrderAccess(orderId);
      token = access && access.access_token;
      var snap = R.readSnapshot();
      if (snap && snap.receipt && snap.receipt.order_id === orderId) {
        // The exact-order receipt wins over an older saved access.
        token = snap.receipt.access_token;
        R.saveOrderAccess(snap.receipt);
      }
      return R.settleOutcome(orderId).then(function (outcome) { if (outcome) showWarning = R.showsWarning(outcome); });
    }).catch(function () {
      // Never hide a possibly preserved cart because its record failed.
      showWarning = true;
      if (!token) throw new Error('recovery');
    }).then(function () {
      warn(showWarning);
      if (!token) {
        stateView('error', 'Esta sesión no tiene acceso a ese pedido. Vuelve al checkout o abre el enlace seguro enviado por la tienda.');
        return;
      }
      // _finalizeTransferCheckoutSessionOnEntry: a transfer has no callback
      // to close the attempt later.
      var snap = R.readSnapshot();
      var transfer = snap && snap.receipt && snap.receipt.order_id === orderId && snap.handoff.payment_method === 'transfer';
      return (transfer ? consumeCart().then(function () { R.takeTransferReceipt(orderId); }) : Promise.resolve())
        .catch(function () { warn(true); })
        .then(function () {
          if (!statusGroup) return load(0);
          show('loading');
          return processCallback()
            .catch(function () { return PENDING_MESSAGE; })
            .then(function (message) { paymentMessage = message; return load(800); });
        });
    }, function () {
      warn(true);
      stateView('error', 'No pudimos abrir la recuperación segura de este pedido. Reinicia la aplicación e inténtalo nuevamente.');
    });
  }

  // ---- actions --------------------------------------------------------------
  function busy(btn, on) {
    btn.disabled = on;
    btn.classList.toggle('busy', on);
    var spin = btn.querySelector('.od-spin');
    if (spin) spin.hidden = !on;
  }
  // _retryMercadoPagoPayment
  function retry(btn) {
    if (btn.disabled || !current) return;
    var label = $('[data-od-retry-label]'), before = label.textContent;
    busy(btn, true);
    label.textContent = 'ABRIENDO MERCADOPAGO';
    var access = token || ((R.readOrderAccess(orderId) || {}).access_token);
    (access ? call('/functions/v1/mercadopago-create-preference', { order_id: orderId, order_access_token: access }) : Promise.reject(new Error('access')))
      .then(function (pref) {
        var init = pref && pref.init_point;
        if (typeof init !== 'string' || !init) throw new Error('init_point');
        // WebUtils.openUrl: the same tab.
        location.assign(init);
      })
      .catch(function () { toast('No pudimos reintentar el pago. Inténtalo nuevamente en unos minutos.', true, 8); })
      .then(function () { busy(btn, false); label.textContent = before; });
  }
  // _downloadOrderPdf: the server draws it with the order's access.
  function pdf(btn) {
    if (btn.disabled || !token) return;
    busy(btn, true);
    fetch(root.dataset.pdfUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ order_id: orderId, access_token: token })
    }).then(function (r) {
      if (!r.ok) throw new Error('http ' + r.status);
      return r.blob();
    }).then(function (blob) {
      var url = URL.createObjectURL(blob), a = document.createElement('a');
      a.href = url;
      a.download = 'pedido_' + ((current && current.order.number) || orderId) + '.pdf';
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
    }).catch(function () {
      toast('No pudimos generar el resumen. Inténtalo nuevamente.', true);
    }).then(function () { busy(btn, false); });
  }
  // _acknowledgeCartPreservationWarning
  function acknowledge(btn) {
    if (btn.disabled) return;
    busy(btn, true);
    try {
      R.acknowledge(orderId);
      warn(false);
    } catch (e) {
      toast('No pudimos confirmar el aviso. Inténtalo nuevamente.');
    }
    busy(btn, false);
  }
  root.addEventListener('click', function (event) {
    var btn = event.target.closest('[data-act]');
    if (!btn || !root.contains(btn)) return;
    var act = btn.getAttribute('data-act');
    if (act === 'retry') retry(btn);
    else if (act === 'pdf') pdf(btn);
    else if (act === 'ack') acknowledge(btn);
  });

  start();
})();
''';
