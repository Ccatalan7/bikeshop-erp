(function () {
  'use strict';

  const SOURCE = 'AliExpress';
  const CONTENT_VERSION = '0.9.9';
  const DEBUG_PREFIX = `[AE-DEBUG][content][v${CONTENT_VERSION}]`;

  function aeDebug(event, details = {}, level = 'log') {
    try {
      const payload = JSON.stringify({
        event,
        at: new Date().toISOString(),
        ...details,
      });
      const writer = console[level] || console.log;
      writer.call(console, `${DEBUG_PREFIX} ${payload}`);
    } catch (error) {
      console.log(`${DEBUG_PREFIX} ${event} (debug serialization failed: ${String(error)})`);
    }
  }

  function safeDebugUrl(value) {
    const raw = String(value || '').trim();
    if (!raw) return '';
    try {
      const parsed = new URL(raw, globalThis.location && globalThis.location.href);
      const safe = new URL(`${parsed.origin}${parsed.pathname}`);
      ['orderId', 'orderIdList', 'orderNo', 'orderNumber', 'itemId', 'productId'].forEach((key) => {
        const field = parsed.searchParams.get(key);
        if (field) safe.searchParams.set(key, field.slice(0, 80));
      });
      return safe.toString();
    } catch (_) {
      return raw.split('?')[0].slice(0, 240);
    }
  }

  function debugItemSummary(item) {
    return {
      sku: item && item.sku || '',
      itemId: item && item.itemId || '',
      description: String(item && item.description || '').slice(0, 160),
      quantity: Number(item && item.quantity || 0),
      unitPrice: Number(item && item.unitPrice || 0),
      total: Number(item && item.total || 0),
      productUrl: safeDebugUrl(item && item.productUrl || ''),
      hasImage: Boolean(item && item.imageUrl),
    };
  }

  function debugOrderSummary(order) {
    return {
      orderNumber: order && order.orderNumber || '',
      orderDate: order && order.orderDate || '',
      pageUrl: safeDebugUrl(order && order.pageUrl || ''),
      subtotal: order && order.subtotal,
      shipping: order && order.shipping,
      tax: order && order.tax,
      discount: order && order.discount,
      total: order && order.total,
      authoritativeTotals: order && order.__authoritativeTotals === true,
      itemCount: Array.isArray(order && order.items) ? order.items.length : 0,
      items: Array.isArray(order && order.items) ? order.items.map(debugItemSummary) : [],
      warnings: Array.isArray(order && order.warnings) ? order.warnings : [],
    };
  }

  function getPageMetrics() {
    return {
      scrollY: window.scrollY,
      innerWidth: window.innerWidth,
      innerHeight: window.innerHeight,
      scrollHeight: Math.max(
        document.documentElement ? document.documentElement.scrollHeight : 0,
        document.body ? document.body.scrollHeight : 0,
      ),
      devicePixelRatio: window.devicePixelRatio || 1,
    };
  }

  async function scrollToPosition(targetY) {
    const resolvedY = Math.max(0, Number(targetY) || 0);
    window.scrollTo(window.scrollX, resolvedY);
    await new Promise((resolve) => window.setTimeout(resolve, 220));
    return {
      scrollY: window.scrollY,
      innerHeight: window.innerHeight,
      scrollHeight: Math.max(
        document.documentElement ? document.documentElement.scrollHeight : 0,
        document.body ? document.body.scrollHeight : 0,
      ),
    };
  }

  async function extractOrderWithPreload() {
    aeDebug('detail.preload.start', { pageUrl: safeDebugUrl(location.href) });
    await preloadOrderDetailContent();
    aeDebug('detail.preload.complete', {
      pageUrl: safeDebugUrl(location.href),
      expand: globalThis.__AE_EXPAND_DEBUG__ || null,
      totalsCardCaptured: Boolean(globalThis.__AE_TOTALS_CARD_TEXT__),
    });
    const order = extractOrder();
    aeDebug('detail.extract.complete', debugOrderSummary(order));
    return order;
  }

  async function extractProductMediaRowsWithPreload() {
    await preloadOrderDetailContent();
    const text = normalizeText(document.body ? document.body.innerText : '');
    const orderScope = buildOrderScope(text);
    const rowItems = extractItemsFromImageAnchoredRows('CLP', orderScope).map((item) => ({
      sku: item.sku || '',
      imageUrl: item.imageUrl || '',
      productUrl: item.productUrl || '',
      itemId: item.itemId || '',
      title: item.description || '',
    }));
    if (rowItems.length > 0) return rowItems;

    return collectCentralOrderProductImages(orderScope);
  }

  async function extractOrdersListWithPreload(filters = {}) {
    aeDebug('list.preload.start', {
      pageUrl: safeDebugUrl(location.href),
      filters: {
        dateMode: filters.dateMode || '',
        exactDate: filters.exactDate || '',
        fromDate: filters.fromDate || '',
        toDate: filters.toDate || '',
        maxLoadClicks: filters.maxLoadClicks || null,
      },
    });
    const preload = await preloadOrdersListContent(filters || {});
    aeDebug('list.preload.complete', {
      ...preload,
      harvestedOrders: (preload.harvestedOrders || []).length,
    });
    const extracted = extractOrdersList(filters || {});
    // Fusión: la lista virtualizada pierde tarjetas del DOM al hacer scroll,
    // así que la extracción final se completa con la cosecha acumulada.
    {
      const byNumber = new Map();
      for (const order of preload.harvestedOrders || []) {
        byNumber.set(order.orderNumber, order);
      }
      for (const order of extracted.orders || []) {
        const existing = byNumber.get(order.orderNumber);
        if (!existing || (order.items || []).length >= (existing.items || []).length) {
          byNumber.set(order.orderNumber, order);
        }
      }
      const exactDate = String((filters || {}).exactDate || '').trim();
      const fromDate = exactDate || String((filters || {}).fromDate || '').trim();
      const toDate = exactDate || String((filters || {}).toDate || '').trim();
      const dateFilterActive = Boolean(fromDate || toDate);
      extracted.orders = Array.from(byNumber.values())
        .filter((order) => isDateInRange(order.orderDate, fromDate, toDate, dateFilterActive));
      extracted.scannedCount = Math.max(extracted.scannedCount, byNumber.size);
    }
    if (extracted.scannedCount === 0) {
      extracted.warnings.push(
        preload.visibleOrderSignals > 0
          ? `Diagnostico: AliExpress expone ${preload.visibleOrderSignals} pedido(s), pero su nueva tarjeta aun no pudo reconocerse.`
          : `Diagnostico: no se encontraron IDs de pedido visibles (fin: ${preload.terminationReason || 'desconocido'}).`,
      );
    }
    const result = { ...extracted, preload };
    aeDebug('list.extract.complete', {
      scannedCount: result.scannedCount,
      matchedCount: result.orders.length,
      warnings: result.warnings,
      orders: result.orders.map(debugOrderSummary),
    });
    return result;
  }

  function getVisibleProductImageRects() {
    const text = normalizeText(document.body ? document.body.innerText : '');
    const orderScope = buildOrderScope(text);
    return collectVisibleOrderProductImageRects(orderScope);
  }

  globalThis.__ALIEXPRESS_INVOICE_BRIDGE__ = {
    version: CONTENT_VERSION,
    extractOrder: extractOrderWithPreload,
    extractProductMediaRows: extractProductMediaRowsWithPreload,
    extractOrdersList: extractOrdersListWithPreload,
    // Recorrido gobernado desde Dart (ver el bloque de pasos atómicos).
    ordersListBeginSteppedRun,
    ordersListDebugTail,
    ordersListScrollTo,
    ordersListHarvestStep,
    ordersListClickLoadMore,
    ordersListFinishSteppedRun,
    ordersApiProbeInstall,
    ordersApiProbeRead,
    ordersApiShapeProbe,
    ordersApiScopeProbe,
    ordersApiCollect,
    visibleProductImageRects: getVisibleProductImageRects,
    getPageMetrics,
    scrollTo: scrollToPosition,
    diagnoseOrdersList,
    _testing: {
      extractOrderListNumber,
      extractOrderListDate,
      extractOrderNumberFromHref,
      findOrderListDetailUrl,
      loadMoreTextScore,
      extractTotalsFromTextBlob,
      cardTotalsBalance,
      dedupeExtractedItems,
      collapseOrderListItemCandidates,
      parseApiOrderDate,
      parseApiMoney,
      mapApiOrder,
      ordersApiParamsForPage,
      ordersApiTemplateSummary,
      ordersApiResponseSummary,
      ordersApiScopeProbe,
    },
  };

  aeDebug('bridge.installed', {
    pageUrl: safeDebugUrl(globalThis.location && globalThis.location.href),
    host: globalThis.chrome && globalThis.chrome.runtime ? 'chrome-extension' : 'erp-webview',
  });

  if (typeof globalThis.__ALIEXPRESS_INVOICE_CONTENT_CLEANUP__ === 'function') {
    try {
      globalThis.__ALIEXPRESS_INVOICE_CONTENT_CLEANUP__();
    } catch (_error) {
      // Ignore stale cleanup failures and keep installing the fresh bridge.
    }
  }

  const onMessage = (message, _sender, sendResponse) => {
    if (!message) return false;

    if (message.type === 'ALIEXPRESS_PING') {
      sendResponse({ ok: true, version: CONTENT_VERSION });
      return false;
    }

    if (message.type === 'ALIEXPRESS_EXTRACT_ORDER') {
      (async () => {
        try {
          sendResponse({ ok: true, order: await extractOrderWithPreload() });
        } catch (error) {
          sendResponse({
            ok: false,
            error: error && error.message ? error.message : String(error),
          });
        }
      })();
      return true;
    }

    if (message.type === 'ALIEXPRESS_PAGE_METRICS') {
      try {
        sendResponse({ ok: true, metrics: getPageMetrics() });
      } catch (error) {
        sendResponse({ ok: false, error: error.message || String(error) });
      }
      return false;
    }

    if (message.type === 'ALIEXPRESS_SCROLL_TO') {
      (async () => {
        try {
          sendResponse({ ok: true, ...(await scrollToPosition(message.y)) });
        } catch (error) {
          sendResponse({ ok: false, error: error.message || String(error) });
        }
      })();
      return true;
    }

    return false;
  };

  const extensionRuntime = globalThis.chrome && globalThis.chrome.runtime;
  if (extensionRuntime && extensionRuntime.onMessage) {
    extensionRuntime.onMessage.addListener(onMessage);
    globalThis.__ALIEXPRESS_INVOICE_CONTENT_CLEANUP__ = () => {
      extensionRuntime.onMessage.removeListener(onMessage);
    };
  } else {
    // The ERP's embedded WebView reuses this extractor without Chrome's
    // extension messaging API. It is installed at document start, so begin
    // observing immediately: waiting until the user chooses a date misses the
    // page's first real request and leaves the calendar without an API
    // template to preload its date index. Chrome keeps its explicit probe
    // lifecycle unchanged.
    // La sonda depende de estado declarado más abajo en este mismo bundle.
    // La microtarea corre apenas termina la instalación síncrona del script,
    // todavía antes de que la página despache su siguiente tarea de red.
    Promise.resolve().then(() => ordersApiProbeInstall());
    globalThis.__ALIEXPRESS_INVOICE_CONTENT_CLEANUP__ = () => {};
  }

  async function preloadOrderDetailContent() {
    const initialX = window.scrollX;
    const initialY = window.scrollY;
    const viewportHeight = window.innerHeight || 800;
    const scrollHeight = Math.max(
      document.documentElement ? document.documentElement.scrollHeight : 0,
      document.body ? document.body.scrollHeight : 0,
    );
    const maxY = Math.max(0, scrollHeight - viewportHeight);
    const step = Math.max(420, Math.floor(viewportHeight * 0.72));
    const endY = Math.min(maxY, initialY + Math.max(5200, viewportHeight * 5));

    for (let y = initialY; y <= endY; y += step) {
      window.scrollTo(initialX, y);
      await sleep(90);
    }

    if (endY < maxY) {
      window.scrollTo(initialX, Math.min(maxY, endY + step));
      await sleep(90);
    }

    // [v0.3.51] Expand collapsed totals breakdown (Shipping / AliExpress Coupons / Tax) before extracting.
    globalThis.__AE_EXPAND_DEBUG__ = null;
    globalThis.__AE_TOTALS_CARD_TEXT__ = null;
    try {
      globalThis.__AE_EXPAND_DEBUG__ = await expandOrderTotalsBreakdown();
    } catch (error) {
      globalThis.__AE_EXPAND_DEBUG__ = { error: String((error && error.message) || error) };
    }

    window.scrollTo(initialX, initialY);
    await sleep(70);
  }

  // [v0.3.51] AliExpress order detail pages render the totals card with Shipping/Coupons/Tax
  // collapsed behind a chevron next to the Subtotal value. Until that chevron is clicked, the
  // page text only contains "Subtotal $X / Total $Y" and the extractor cannot see the breakdown.
  // This helper finds the totals card around any "Subtotal" label and aggressively clicks any
  // chevron / toggle / arrow it can find inside or right next to it, using multiple event
  // strategies (synthetic pointer + mouse + click) because some chevrons are SVGs without
  // onclick handlers and only respond to dispatched mouse events.
  async function expandOrderTotalsBreakdown() {
    const debug = {
      labelMatches: 0,
      cardsConsidered: 0,
      togglesTried: 0,
      breakdownVisibleBefore: false,
      breakdownVisibleAfter: false,
      lastCardTextSample: '',
    };

    const labelNodes = findSubtotalLabelNodes();
    debug.labelMatches = labelNodes.length;
    if (labelNodes.length === 0) return debug;

    // First pass: any totals card already showing the breakdown -> nothing to do.
    const cards = [];
    const seenCards = new Set();
    for (const labelNode of labelNodes) {
      const card = findTotalsCard(labelNode);
      if (!card || seenCards.has(card)) continue;
      seenCards.add(card);
      cards.push(card);
    }
    debug.cardsConsidered = cards.length;
    debug.breakdownVisibleBefore = cards.some((card) => totalsBreakdownVisible(card));
    if (debug.breakdownVisibleBefore) {
      debug.breakdownVisibleAfter = true;
      debug.lastCardTextSample = (cards[0].innerText || '').slice(0, 400);
      return debug;
    }

    // Second pass: aggressively click anything that looks like a chevron in or near each card.
    for (const card of cards) {
      const region = expandedRegionFor(card);
      const toggles = collectExpandToggles(region);
      for (const toggle of toggles) {
        debug.togglesTried += 1;
        try {
          fireSyntheticClick(toggle);
        } catch (_) { /* continue */ }
        await sleep(160);
        if (totalsBreakdownVisible(card)) break;
      }
      if (totalsBreakdownVisible(card)) break;
    }

    // Final wait + status capture.
    await sleep(220);
    debug.breakdownVisibleAfter = cards.some((card) => totalsBreakdownVisible(card));
    // Capture the cleanest totals card text so extractTotals can use it as the authoritative
    // source. The card is small and only contains real Subtotal/Shipping/Tax/Discount/Total
    // rows -- it cannot be polluted by promo text like "$800 coupon if delayed".
    globalThis.__AE_TOTALS_CARD_TEXT__ = bestTotalsCardText(cards);
    debug.lastCardTextSample = (cards[0] && cards[0].innerText ? cards[0].innerText : '').slice(0, 400);
    return debug;
  }

  function bestTotalsCardText(cards) {
    const candidates = [];
    for (const card of cards) {
      for (const text of [card.innerText || '', card.textContent || '']) {
        if (!text || !/subtotal/i.test(text) || !/\btotal\b/i.test(text)) continue;
        const totals = extractTotalsFromTextBlob(text);
        let score = scoreTotalsCandidate(totals);
        if (cardTotalsBalance(totals)) score += 2000;
        score -= Math.max(0, text.length - 1800) / 10;
        candidates.push({ text, score });
      }
    }
    candidates.sort((a, b) => b.score - a.score || a.text.length - b.text.length);
    return candidates[0]?.text || null;
  }

  function findSubtotalLabelNodes() {
    const matches = [];
    const candidates = document.querySelectorAll('div, span, p, td, th, li, dt, label, strong, b');
    for (const element of candidates) {
      const text = (element.innerText || element.textContent || '').replace(/\s+/g, ' ').trim().toLowerCase();
      if (!text) continue;
      if (text === 'subtotal' || text === 'subtotal:' || text.startsWith('subtotal productos')) {
        matches.push(element);
      } else if (text.length <= 24 && /^subtotal\b/.test(text)) {
        matches.push(element);
      }
      if (matches.length >= 24) break;
    }
    return matches;
  }

  function findTotalsCard(labelNode) {
    let node = labelNode;
    let bestSmall = null;
    for (let depth = 0; depth < 10 && node && node.parentElement; depth += 1) {
      node = node.parentElement;
      const text = (node.innerText || node.textContent || '').toLowerCase();
      if (!text.includes('subtotal') || !text.includes('total')) continue;
      // Prefer the smallest container that still has both Subtotal and Total.
      if (!bestSmall || (text.length < (bestSmall.innerText || bestSmall.textContent || '').length)) {
        bestSmall = node;
      }
      if (text.length <= 800) return node;
    }
    return bestSmall || labelNode;
  }

  // Sometimes the chevron lives in a sibling block right above/below the totals card.
  // We expand the search region to include the parent chain that still looks compact.
  function expandedRegionFor(card) {
    let region = card;
    let node = card.parentElement;
    for (let depth = 0; depth < 3 && node; depth += 1) {
      const text = (node.innerText || node.textContent || '').toLowerCase();
      if (!text.includes('subtotal') || !text.includes('total')) break;
      if (text.length > 1600) break;
      region = node;
      node = node.parentElement;
    }
    return region;
  }

  function totalsBreakdownVisible(card) {
    const text = (card.innerText || card.textContent || '').toLowerCase();
    return /\b(shipping|delivery|env[ií]o|flete|tax|iva|impuesto|coupon|cup[oó]n|coins?|monedas?|descuento|discount)\b/.test(text);
  }

  function collectExpandToggles(region) {
    const toggles = [];
    const seen = new Set();
    const subtotalRects = findSubtotalLabelNodes()
      .filter((label) => region === label || (region.contains && region.contains(label)))
      .map((label) => label.getBoundingClientRect && label.getBoundingClientRect())
      .filter(Boolean);
    const selectorList = [
      '[aria-expanded]',
      '[class*="arrow" i]',
      '[class*="chevron" i]',
      '[class*="fold" i]',
      '[class*="expand" i]',
      '[class*="toggle" i]',
      '[class*="caret" i]',
      'svg',
      'i',
    ];
    for (const selector of selectorList) {
      let found;
      try { found = region.querySelectorAll(selector); } catch (_) { continue; }
      for (const element of found) {
        const target = resolveClickableAncestor(element) || element;
        if (!target || seen.has(target)) continue;
        const rect = target.getBoundingClientRect ? target.getBoundingClientRect() : null;
        if (!rect || rect.width <= 0 || rect.height <= 0 || rect.width > 220 || rect.height > 80) continue;
        const text = normalizeText(target.innerText || target.textContent || target.getAttribute?.('aria-label') || '')
          .replace(/\s+/g, ' ')
          .trim();
        if (/add\s+to\s+cart|returns?|refunds?|buy\s+now|contact|chat/i.test(text)) continue;
        const classText = `${element.className || ''} ${target.className || ''} ${target.getAttribute?.('aria-label') || ''}`;
        const explicit = target.getAttribute?.('aria-expanded') !== null
          || /arrow|chevron|fold|expand|toggle|caret/i.test(classText);
        const nearby = subtotalRects.length === 0 || subtotalRects.some((labelRect) => {
          const vertical = Math.abs((rect.top + rect.height / 2) - (labelRect.top + labelRect.height / 2));
          const horizontal = Math.abs((rect.left + rect.width / 2) - (labelRect.left + labelRect.width / 2));
          return vertical <= 140 && horizontal <= 760;
        });
        if (!nearby || (!explicit && !['svg', 'I'].includes(element.tagName))) continue;
        seen.add(target);
        toggles.push({ target, score: (explicit ? 100 : 0) + rect.left / 1000 });
      }
    }
    return toggles.sort((a, b) => b.score - a.score).map((entry) => entry.target);
  }

  function resolveClickableAncestor(element) {
    let node = element;
    for (let depth = 0; depth < 5 && node; depth += 1) {
      if (node.tagName === 'BUTTON' || node.tagName === 'A') return node;
      const role = node.getAttribute && node.getAttribute('role');
      if (role === 'button') return node;
      const ariaExpanded = node.getAttribute && node.getAttribute('aria-expanded');
      if (ariaExpanded !== null && ariaExpanded !== undefined) return node;
      if (typeof node.onclick === 'function') return node;
      const tabIndex = node.getAttribute && node.getAttribute('tabindex');
      if (tabIndex && tabIndex !== '-1') return node;
      node = node.parentElement;
    }
    return element;
  }

  // Some AliExpress chevrons are SVGs with React handlers attached only to mousedown/pointerdown,
  // not the synthetic click event. Fire the full sequence to cover all bases.
  function fireSyntheticClick(target) {
    if (!target) return;
    const rect = target.getBoundingClientRect ? target.getBoundingClientRect() : null;
    const x = rect ? rect.left + rect.width / 2 : 0;
    const y = rect ? rect.top + rect.height / 2 : 0;
    const eventInit = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, button: 0 };
    try { target.dispatchEvent(new PointerEvent('pointerdown', { ...eventInit, pointerType: 'mouse' })); } catch (_) {}
    try { target.dispatchEvent(new MouseEvent('mousedown', eventInit)); } catch (_) {}
    try { target.dispatchEvent(new PointerEvent('pointerup', { ...eventInit, pointerType: 'mouse' })); } catch (_) {}
    try { target.dispatchEvent(new MouseEvent('mouseup', eventInit)); } catch (_) {}
    try { target.dispatchEvent(new MouseEvent('click', eventInit)); } catch (_) {}
    try { if (typeof target.click === 'function') target.click(); } catch (_) {}
  }

  // Cosecha acumulativa de la lista virtualizada. Vive a nivel de módulo
  // porque la leen dos funciones hermanas (`preloadOrdersListContent` y
  // `traverseLoadedOrdersList`): en v0.4.7 era `const` local de la primera y
  // la segunda moría con ReferenceError en el primer ciclo (2026-08-05).
  const harvestedOrders = new Map();
  const harvestedSignatures = new Set();

  // Cosecha por paso de scroll, barata por diseño.
  //
  // La lista está virtualizada: una tarjeta que sale de la ventana visible se
  // desmonta, así que hay que cosechar durante el recorrido y no sólo al
  // final. Pero reconstruir TODAS las tarjetas en cada paso cuesta ~1,5 s por
  // llamada y con ello el recorrido no terminaba (2026-08-06). Aquí el paso
  // caro se paga una sola vez por pedido: los números ya cosechados se
  // descartan leyendo sólo nodos de texto (lineal, sin layout).
  function harvestVisibleOrders() {
    const pending = [];
    for (const element of orderNumberSeedElements(ordersListScope())) {
      const raw = element.textContent || '';
      const match = raw.match(/(\d{10,})/);
      if (!match) continue;
      const number = match[1];
      if (harvestedSignatures.has(number)) continue;
      pending.push(number);
    }
    if (!pending.length) return;

    for (const card of collectOrderListCards()) {
      const order = buildOrderListInvoice(card);
      if (!order || !order.orderNumber) continue;
      harvestedSignatures.add(order.orderNumber);
      const existing = harvestedOrders.get(order.orderNumber);
      // Preferir la captura con más ítems: una tarjeta a medio renderizar
      // no debe pisar una cosecha completa anterior.
      if (!existing || (order.items || []).length >= (existing.items || []).length) {
        harvestedOrders.set(order.orderNumber, order);
      }
    }
  }

  // ── Descubrimiento del endpoint real de pedidos ────────────────────────
  //
  // La página construye el listado llamando a su propia API con la sesión ya
  // iniciada. Leer esa respuesta es infinitamente más preciso que deducir los
  // pedidos del DOM: trae fechas, montos e ítems exactos, y su paginación es
  // un número de página, no un scroll con lista virtualizada. Esta sonda
  // observa qué llamadas hace la página para saber a cuál pedirle los datos.
  const observedOrderApiCalls = [];
  let orderApiProbeInstalled = false;

  function looksLikeOrderApiUrl(url) {
    return /order/i.test(url) &&
      !/\.(png|jpe?g|gif|webp|css|js|svg|woff2?)(\?|$)/i.test(url);
  }

  function recordOrderApiCall(entry) {
    if (observedOrderApiCalls.length >= 40) return;
    observedOrderApiCalls.push(entry);
  }

  // El cuerpo se guarda COMPLETO aparte: la copia recortada sirve para el log,
  // pero la plantilla de la petición necesita el JSON entero o no parsea.
  const observedOrderApiBodies = [];
  function recordOrderApiBody(body) {
    if (typeof body !== 'string' || observedOrderApiBodies.length >= 10) return;
    observedOrderApiBodies.push(body);
  }

  function ordersApiProbeInstall() {
    if (orderApiProbeInstalled) {
      return { installed: true, alreadyInstalled: true };
    }
    orderApiProbeInstalled = true;

    const originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
      window.fetch = function patchedFetch(input, init) {
        try {
          const url = typeof input === 'string' ? input : (input && input.url) || '';
          if (looksLikeOrderApiUrl(url)) {
            recordOrderApiCall({
              via: 'fetch',
              url: String(url).slice(0, 400),
              method: (init && init.method) || (input && input.method) || 'GET',
              body: init && typeof init.body === 'string' ? init.body.slice(0, 600) : null,
            });
            if (init && typeof init.body === 'string') recordOrderApiBody(init.body);
          }
        } catch (_) {}
        return originalFetch.apply(this, arguments);
      };
    }

    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function patchedOpen(method, url) {
      try {
        this.__aeMethod = method;
        this.__aeUrl = String(url || '');
      } catch (_) {}
      return originalOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function patchedSend(body) {
      try {
        if (this.__aeUrl && looksLikeOrderApiUrl(this.__aeUrl)) {
          recordOrderApiCall({
            via: 'xhr',
            url: this.__aeUrl.slice(0, 400),
            method: this.__aeMethod || 'GET',
            body: typeof body === 'string' ? body.slice(0, 400) : null,
          });
          recordOrderApiBody(body);
        }
      } catch (_) {}
      return originalSend.apply(this, arguments);
    };

    return { installed: true, alreadyInstalled: false };
  }

  // ── Recolección por la API de pedidos ──────────────────────────────────
  //
  // La página pide su listado a `mtop.aliexpress.trade.buyer.order.list` y
  // expone su propio cliente firmado en `window.lib.mtop`. Pedirle los datos
  // ahí es exacto y barato: paginación por número de página, fechas y montos
  // tal cual los tiene AliExpress, sin scroll, sin lista virtualizada, sin
  // depender del rótulo del botón ni del carrusel de recomendaciones.
  //
  // El cuerpo de la petición no se inventa: se toma el de una llamada real de
  // esta misma sesión (los ids de módulo varían por cuenta y versión) y sólo
  // se le cambia el único campo JSON `pageIndex`. Una plantilla ambigua se
  // rechaza; una expresión regular podría cambiar por accidente otro número.
  const ORDERS_API = 'mtop.aliexpress.trade.buyer.order.list';
  let ordersApiTemplateParams = null;

  function parseOrdersApiTemplateParams() {
    if (!ordersApiTemplateParams) return null;
    try {
      const parsed = JSON.parse(ordersApiTemplateParams);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
        ? parsed
        : null;
    } catch (_) {
      return null;
    }
  }

  function parsedEmbeddedJson(value) {
    if (typeof value !== 'string') return null;
    const trimmed = value.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      const parsed = JSON.parse(trimmed);
      return parsed && typeof parsed === 'object' ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  function findPageIndexSlots(value, slots = [], path = '', depth = 0) {
    if (depth > 8) return slots;
    const embedded = parsedEmbeddedJson(value);
    if (embedded) {
      findPageIndexSlots(embedded, slots, `${path}.$json`, depth + 1);
      return slots;
    }
    if (!value || typeof value !== 'object') return slots;
    for (const key of Object.keys(value)) {
      if (String(key).toLowerCase() === 'pageindex') {
        slots.push({ path: path ? `${path}.${key}` : key });
        continue;
      }
      findPageIndexSlots(
        value[key],
        slots,
        path ? `${path}.${key}` : key,
        depth + 1,
      );
    }
    return slots;
  }

  function rewriteStructuredPageIndexes(value, pageIndex, depth = 0) {
    if (depth > 8) return { value, count: 0 };
    const embedded = parsedEmbeddedJson(value);
    if (embedded) {
      const rewritten = rewriteStructuredPageIndexes(
        embedded,
        pageIndex,
        depth + 1,
      );
      return {
        value: rewritten.count > 0 ? JSON.stringify(rewritten.value) : value,
        count: rewritten.count,
      };
    }
    if (!value || typeof value !== 'object') return { value, count: 0 };
    const clone = Array.isArray(value) ? [] : {};
    let count = 0;
    for (const key of Object.keys(value)) {
      const original = value[key];
      if (String(key).toLowerCase() === 'pageindex' &&
          (typeof original === 'number' || typeof original === 'string')) {
        clone[key] = typeof original === 'string'
          ? String(pageIndex)
          : Number(pageIndex);
        count += 1;
        continue;
      }
      const child = rewriteStructuredPageIndexes(original, pageIndex, depth + 1);
      clone[key] = child.value;
      count += child.count;
    }
    return { value: clone, count };
  }

  function expandEmbeddedJson(value, depth = 0) {
    if (depth > 8) return value;
    const embedded = parsedEmbeddedJson(value);
    if (embedded) return expandEmbeddedJson(embedded, depth + 1);
    if (Array.isArray(value)) {
      return value.map((entry) => expandEmbeddedJson(entry, depth + 1));
    }
    if (!value || typeof value !== 'object') return value;
    const expanded = {};
    for (const key of Object.keys(value)) {
      expanded[key] = expandEmbeddedJson(value[key], depth + 1);
    }
    return expanded;
  }

  function isSafeDiagnosticKey(key) {
    const normalized = String(key || '')
      .replace(/[^a-z0-9]/gi, '')
      .toLowerCase();
    if (!normalized) return false;
    return ![
      'token', 'cookie', 'auth', 'signature', 'password', 'secret',
      'session', 'credential', 'csrf', 'accesskey', 'refreshkey',
    ].some((sensitive) => normalized.includes(sensitive));
  }

  function isOrderPayloadKey(key) {
    const text = String(key || '');
    return /^pc_om_list_order_\d+$/.test(text) ||
      /^(order|orders|orderList|orderLines|items|products)$/i.test(text);
  }

  function diagnosticKeyPaths(
    value,
    { prefix = '', depth = 0, skipOrderPayload = false, out = [] } = {},
  ) {
    if (!value || typeof value !== 'object' || depth > 6 || out.length >= 160) {
      return out;
    }
    const source = Array.isArray(value) ? value.slice(0, 1) : value;
    for (const rawKey of Object.keys(source).slice(0, 80)) {
      const key = Array.isArray(source) ? '[]' : rawKey;
      if (!Array.isArray(source) && !isSafeDiagnosticKey(key)) continue;
      if (!Array.isArray(source) && skipOrderPayload && isOrderPayloadKey(key)) {
        continue;
      }
      const path = prefix ? `${prefix}.${key}` : key;
      if (!out.includes(path)) out.push(path);
      diagnosticKeyPaths(source[rawKey], {
        prefix: path,
        depth: depth + 1,
        skipOrderPayload,
        out,
      });
      if (out.length >= 160) break;
    }
    return out;
  }

  const DIAGNOSTIC_TEMPLATE_FIELDS = new Set([
    'pageindex', 'pagesize', 'pageno', 'currentpage', 'startdate',
    'enddate', 'fromdate', 'todate', 'daterange', 'year', 'status',
    'orderstatus', 'filter', 'tab', 'timerange', 'statustab', 'timeoption',
    'searchoption', 'searchinput', 'hasmore',
  ]);
  const DIAGNOSTIC_PAGINATION_FIELDS = new Set([
    'hasnext', 'totalpage', 'totalpages', 'totalcount', 'pagesize',
    'totalnum', 'currentpage', 'pageindex', 'nextpage', 'pagecount',
    'hasmore', 'hasmoretext',
  ]);

  function diagnosticScalarFields(
    value,
    allowedFields,
    { prefix = '', depth = 0, skipOrderPayload = false, out = {} } = {},
  ) {
    if (!value || typeof value !== 'object' ||
        depth > 6 || Object.keys(out).length >= 80) {
      return out;
    }
    for (const key of Object.keys(value).slice(0, 80)) {
      if (!isSafeDiagnosticKey(key)) continue;
      if (skipOrderPayload && isOrderPayloadKey(key)) continue;
      const path = prefix ? `${prefix}.${key}` : key;
      const field = String(key).replace(/[^a-z0-9]/gi, '').toLowerCase();
      const candidate = value[key];
      if (allowedFields.has(field) &&
          (typeof candidate === 'string' ||
            typeof candidate === 'number' ||
            typeof candidate === 'boolean' ||
            candidate === null)) {
        out[path] = typeof candidate === 'string'
          ? candidate.slice(0, 80)
          : candidate;
      }
      diagnosticScalarFields(candidate, allowedFields, {
        prefix: path,
        depth: depth + 1,
        skipOrderPayload,
        out,
      });
    }
    return out;
  }

  function ordersApiTemplateSummary() {
    const parsed = parseOrdersApiTemplateParams();
    if (!parsed) return { available: false, keyPaths: [], fields: {} };
    const expanded = expandEmbeddedJson(parsed);
    return {
      available: true,
      keyPaths: diagnosticKeyPaths(expanded),
      fields: diagnosticScalarFields(expanded, DIAGNOSTIC_TEMPLATE_FIELDS),
      pageIndexSlots: findPageIndexSlots(parsed).length,
    };
  }

  function ordersApiResponseSummary(response) {
    const modules = (response && response.data && response.data.data) || {};
    return {
      keyPaths: diagnosticKeyPaths(response, { skipOrderPayload: true }),
      pagination: diagnosticScalarFields(
        response,
        DIAGNOSTIC_PAGINATION_FIELDS,
        { skipOrderPayload: true },
      ),
      filters: diagnosticScalarFields(
        response,
        DIAGNOSTIC_TEMPLATE_FIELDS,
        { skipOrderPayload: true },
      ),
      filterOptions: ordersApiFilterOptions(modules),
      orderModuleCount: Object.keys(modules)
        .filter((key) => /^pc_om_list_order_\d+$/.test(key)).length,
    };
  }

  function safeFilterOptions(value, textKeys) {
    if (!Array.isArray(value)) return [];
    return value.slice(0, 30).map((entry) => {
      if (!entry || typeof entry !== 'object') return null;
      const code = entry.code;
      if (typeof code !== 'string' && typeof code !== 'number') return null;
      const result = { code: String(code).slice(0, 40) };
      for (const key of textKeys) {
        if (typeof entry[key] === 'string') {
          result[key] = entry[key].slice(0, 80);
          break;
        }
      }
      return result;
    }).filter(Boolean);
  }

  function ordersApiFilterOptions(modules) {
    const time = [];
    const status = [];
    for (const key of Object.keys(modules || {})) {
      if (!/^pc_om_list_header(?:_|$)/.test(key)) continue;
      const fields = modules[key] && modules[key].fields;
      if (!fields || typeof fields !== 'object') continue;
      time.push(...safeFilterOptions(fields.searchTimeOptions, ['text', 'title']));
      status.push(...safeFilterOptions(fields.statusTabList, ['title', 'text']));
      if (fields.tailStatusTab && typeof fields.tailStatusTab === 'object') {
        status.push(...safeFilterOptions([fields.tailStatusTab], ['title', 'text']));
      }
    }
    const unique = (options) => options.filter(
      (entry, index) => options.findIndex((other) => other.code === entry.code) === index,
    );
    return { time: unique(time), status: unique(status) };
  }

  function captureOrdersApiTemplate() {
    if (ordersApiTemplateParams) return true;
    for (const body of observedOrderApiBodies) {
      if (!/pageIndex/.test(body)) continue;
      try {
        const decoded = decodeURIComponent(body.replace(/^data=/, ''));
        const parsed = JSON.parse(decoded);
        if (parsed && typeof parsed.params === 'string' &&
            /pageIndex/.test(parsed.params)) {
          ordersApiTemplateParams = parsed.params;
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  function rewriteStructuredScalar(value, fieldName, replacement, depth = 0) {
    if (depth > 8) return { value, count: 0 };
    const embedded = parsedEmbeddedJson(value);
    if (embedded) {
      const rewritten = rewriteStructuredScalar(
        embedded,
        fieldName,
        replacement,
        depth + 1,
      );
      return {
        value: rewritten.count > 0 ? JSON.stringify(rewritten.value) : value,
        count: rewritten.count,
      };
    }
    if (!value || typeof value !== 'object') return { value, count: 0 };
    const clone = Array.isArray(value) ? [] : {};
    let count = 0;
    for (const key of Object.keys(value)) {
      const original = value[key];
      if (String(key).toLowerCase() === String(fieldName).toLowerCase() &&
          (typeof original === 'number' || typeof original === 'string' ||
            typeof original === 'boolean')) {
        if (typeof original === 'number') clone[key] = Number(replacement);
        else if (typeof original === 'boolean') clone[key] = Boolean(replacement);
        else clone[key] = String(replacement);
        count += 1;
        continue;
      }
      const child = rewriteStructuredScalar(
        original,
        fieldName,
        replacement,
        depth + 1,
      );
      clone[key] = child.value;
      count += child.count;
    }
    return { value: clone, count };
  }

  function ordersApiParamsForPage(pageIndex, overrides = {}) {
    const parsed = parseOrdersApiTemplateParams();
    if (!parsed) return null;
    let rewritten = rewriteStructuredPageIndexes(parsed, pageIndex);
    if (rewritten.count !== 1) return null;
    for (const fieldName of ['statusTab', 'timeOption']) {
      if (!Object.prototype.hasOwnProperty.call(overrides, fieldName)) continue;
      rewritten = rewriteStructuredScalar(
        rewritten.value,
        fieldName,
        overrides[fieldName],
      );
      if (rewritten.count !== 1) return null;
    }
    return JSON.stringify(rewritten.value);
  }

  function ordersApiAvailable() {
    const mtop = window.lib && window.lib.mtop;
    return Boolean(mtop && typeof mtop.request === 'function');
  }

  function ordersApiFetchPage(pageIndex, overrides = {}) {
    const mtop = window.lib && window.lib.mtop;
    const params = ordersApiParamsForPage(pageIndex, overrides);
    if (!mtop) {
      return Promise.reject(new Error('API de pedidos no disponible.'));
    }
    if (!params) {
      return Promise.reject(
        new Error('La plantilla de pedidos no tiene un pageIndex único.'),
      );
    }
    return mtop.request({
      api: ORDERS_API,
      v: '1.0',
      type: 'POST',
      dataType: 'json',
      timeout: 15000,
      data: { params },
    });
  }

  const API_MONTHS = {
    jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
    jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
    ene: 1, abr: 4, ago: 8, dic: 12,
  };

  /// «Jun 15, 2026» → «2026-06-15». Devuelve '' si no reconoce la forma, para
  /// que un formato nuevo se note como dato faltante y no como fecha inventada.
  function parseApiOrderDate(text) {
    const value = String(text || '').trim();
    const match = value.match(/^([A-Za-zÁÉÍÓÚáéíóú]{3,})\.?\s+(\d{1,2}),?\s+(\d{4})$/);
    if (!match) return '';
    const month = API_MONTHS[match[1].slice(0, 3).toLowerCase()];
    if (!month) return '';
    return `${match[3]}-${String(month).padStart(2, '0')}-${match[2].padStart(2, '0')}`;
  }

  /// «CLP 13,941» → 13941. El peso chileno no usa decimales y AliExpress
  /// separa miles con coma; se conserva la parte decimal sólo si viene.
  function parseApiMoney(text) {
    const value = String(text || '').replace(/[^0-9.,]/g, '').trim();
    if (!value) return null;
    const lastComma = value.lastIndexOf(',');
    const lastDot = value.lastIndexOf('.');
    const decimalSeparator = lastComma > lastDot ? ',' : (lastDot > -1 ? '.' : '');
    let normalized = value;
    if (decimalSeparator) {
      const tail = value.slice(value.lastIndexOf(decimalSeparator) + 1);
      // Tres dígitos tras el separador es agrupación de miles, no decimales.
      if (tail.length === 3) {
        normalized = value.replace(/[.,]/g, '');
      } else {
        normalized = value
          .replace(new RegExp(`\\${decimalSeparator === ',' ? '.' : ','}`, 'g'), '')
          .replace(decimalSeparator, '.');
      }
    }
    const parsed = Number(normalized);
    return Number.isFinite(parsed) ? parsed : null;
  }

  function mapApiOrder(fields) {
    if (!fields || !fields.orderId) return null;
    const orderNumber = String(fields.orderId);
    const orderDate = parseApiOrderDate(fields.orderDateText);
    const total = parseApiMoney(fields.totalPriceText || fields.formatPriceInfo);
    const lines = Array.isArray(fields.orderLines) ? fields.orderLines : [];
    // Agregación por producto y precio: AliExpress puede entregar el mismo
    // artículo en varias líneas de pedido, y son compras reales, no lecturas
    // repetidas. Sumarlas aquí evita que el deduplicador —pensado para el
    // raspado de pantalla, donde una tarjeta sí se lee dos veces— las colapse
    // y pierda unidades: el 2026-04-06 un pedido de 2 botellas entraba como 1
    // y la unidad faltante se absorbía como «ajuste», duplicando el costo
    // unitario que llegaba al inventario (2026-08-06).
    const aggregated = new Map();
    const items = [];
    for (const [lineIndex, line] of lines.entries()) {
      if (!line) continue;
      const quantity = Number(line.quantity) || 1;
      const unitPrice = parseApiMoney(line.formatPriceInfo);
      const variant = Array.isArray(line.skuAttrs)
        ? line.skuAttrs
            .map((attr) => (attr && (attr.value || attr.text || attr.name)) || '')
            .filter(Boolean)
            .join(', ')
        : '';
      const title = String(line.itemTitle || '').trim();
      const immutableVariantKey = immutableVariantKeyFromApiLine(line);
      const item = {
        sku: line.productId ? `AE-${String(line.productId).slice(-8)}` : '',
        itemId: line.productId ? String(line.productId) : '',
        lineTitle: title || null,
        description: variant ? `${title} (${variant})` : title,
        variant,
        // Only a supplier-owned SKU/property identifier may later become an
        // exact ERP alias. The human label remains useful for display and
        // row grouping, but is not durable identity across translations.
        variantKey: immutableVariantKey
          || supplierVariantKey(variant)
          || 'default',
        sourceApiLineOrdinal: lineIndex + 1,
        quantity,
        unitPrice,
        total: unitPrice === null ? null : roundMoney(unitPrice * quantity),
        productUrl: absoluteAliExpressUrl(line.itemDetailUrl),
        imageUrl: absoluteAliExpressUrl(line.itemImgUrl),
      };
      // Mismo producto, misma variante y mismo precio: es la misma compra
      // partida en líneas, así que se suman las unidades.
      const key = immutableVariantKey
        ? `${item.itemId}|${immutableVariantKey}|${item.unitPrice}`
        : `unresolved-line:${lineIndex}`;
      const existing = aggregated.get(key);
      if (existing) {
        existing.quantity += item.quantity;
        existing.total = existing.unitPrice === null
          ? null
          : roundMoney(existing.unitPrice * existing.quantity);
        if (!existing.imageUrl) existing.imageUrl = item.imageUrl;
        continue;
      }
      aggregated.set(key, item);
      items.push(item);
    }
    const detailUrl = absoluteAliExpressUrl(fields.orderDetailUrl) ||
      `https://www.aliexpress.com/p/order/detail.html?orderId=${orderNumber}`;
    return {
      source: 'AliExpress',
      via: 'api',
      generatedAt: new Date().toISOString(),
      extractedAt: new Date().toISOString(),
      pageUrl: detailUrl,
      pageTitle: 'Orders',
      supplierName: 'AliExpress Marketplace',
      supplierTaxId: '',
      orderNumber,
      orderDate,
      currency: String(fields.currencyCode || 'CLP'),
      storeName: String(fields.storeName || ''),
      statusText: String(fields.statusText || ''),
      subtotal: null,
      shipping: null,
      tax: null,
      discount: null,
      total,
      notes: `Pedido AliExpress: ${orderNumber}.\nURL: ${detailUrl}`,
      items,
      warnings: [],
    };
  }

  function absoluteAliExpressUrl(value) {
    const url = String(value || '').trim();
    if (!url) return '';
    if (url.startsWith('//')) return `https:${url}`;
    if (/^https?:\/\//i.test(url)) return url;
    return '';
  }

  function scalarFieldByLeaf(fields, leafName) {
    const normalizedLeaf = String(leafName).toLowerCase();
    const matches = Object.entries(fields || {}).filter(
      ([path]) => String(path).split('.').pop().toLowerCase() === normalizedLeaf,
    );
    return {
      count: matches.length,
      value: matches.length === 1 ? matches[0][1] : null,
    };
  }

  function ordersApiTemplateScope(overrides = {}) {
    const summary = ordersApiTemplateSummary();
    if (!summary.available || summary.pageIndexSlots !== 1) {
      return { ok: false, reason: 'invalid-page-template' };
    }
    const pageSize = scalarFieldByLeaf(summary.fields, 'pageSize');
    const statusTab = scalarFieldByLeaf(summary.fields, 'statusTab');
    const timeOption = scalarFieldByLeaf(summary.fields, 'timeOption');
    const searchOption = scalarFieldByLeaf(summary.fields, 'searchOption');
    const searchInput = scalarFieldByLeaf(summary.fields, 'searchInput');
    if (pageSize.count !== 1 || !Number.isInteger(Number(pageSize.value)) ||
        Number(pageSize.value) <= 0) {
      return { ok: false, reason: 'invalid-page-size-template' };
    }
    if (statusTab.count !== 1 || timeOption.count !== 1 ||
        searchOption.count !== 1) {
      return { ok: false, reason: 'unproven-filter-template' };
    }
    if (String(statusTab.value) !== 'all' || String(timeOption.value) !== 'all' ||
        String(searchOption.value) !== 'order' ||
        (searchInput.count === 1 && String(searchInput.value).trim())) {
      return { ok: false, reason: 'restrictive-filter-template' };
    }
    const scope = {
      statusTab: Object.prototype.hasOwnProperty.call(overrides, 'statusTab')
        ? String(overrides.statusTab)
        : 'all',
      timeOption: Object.prototype.hasOwnProperty.call(overrides, 'timeOption')
        ? String(overrides.timeOption)
        : 'all',
      searchOption: 'order',
      searchInput: '',
      pageSize: Number(pageSize.value),
    };
    if (!ordersApiParamsForPage(1, overrides)) {
      return { ok: false, reason: 'ambiguous-filter-rewrite' };
    }
    return { ok: true, scope };
  }

  function ordersApiResponseState(response, expectedScope, requestedPage) {
    const modules = response && response.data && response.data.data;
    if (!modules || typeof modules !== 'object' || Array.isArray(modules)) {
      return { ok: false, reason: 'invalid-response-envelope' };
    }
    const bodyKeys = Object.keys(modules)
      .filter((key) => /^pc_om_list_body(?:_|$)/.test(key));
    if (bodyKeys.length !== 1) {
      return { ok: false, reason: 'ambiguous-pagination-response' };
    }
    const bodyFields = modules[bodyKeys[0]] && modules[bodyKeys[0]].fields;
    if (!bodyFields || typeof bodyFields !== 'object') {
      return { ok: false, reason: 'missing-pagination-response' };
    }
    const pageIndex = Number(bodyFields.pageIndex);
    const pageSize = Number(bodyFields.pageSize);
    const hasMore = bodyFields.hasMore;
    if (!Number.isInteger(pageIndex) || pageIndex !== requestedPage) {
      return { ok: false, reason: 'unexpected-response-page' };
    }
    if (!Number.isInteger(pageSize) || pageSize !== expectedScope.pageSize) {
      return { ok: false, reason: 'inconsistent-page-size' };
    }
    if (typeof hasMore !== 'boolean') {
      return { ok: false, reason: 'missing-has-more' };
    }

    const actionKeys = Object.keys(modules)
      .filter((key) => /^pc_om_list_header_action(?:_|$)/.test(key));
    let filterEcho = 'absent';
    if (actionKeys.length > 1) {
      return { ok: false, reason: 'ambiguous-filter-response' };
    }
    if (actionKeys.length === 1) {
      const fields = modules[actionKeys[0]] && modules[actionKeys[0]].fields;
      if (!fields || typeof fields !== 'object') {
        return { ok: false, reason: 'invalid-filter-response' };
      }
      const echoed = {
        statusTab: String(fields.statusTab || ''),
        timeOption: String(fields.timeOption || ''),
        searchOption: String(fields.searchOption || ''),
        searchInput: String(fields.searchInput || ''),
      };
      if (echoed.statusTab !== expectedScope.statusTab ||
          echoed.timeOption !== expectedScope.timeOption ||
          echoed.searchOption !== expectedScope.searchOption ||
          echoed.searchInput.trim()) {
        return { ok: false, reason: 'filter-coerced' };
      }
      filterEcho = 'verified';
    }

    const orderKeys = Object.keys(modules)
      .filter((key) => /^pc_om_list_order_\d+$/.test(key));
    return {
      ok: true,
      modules,
      orderKeys,
      pageIndex,
      pageSize,
      hasMore,
      filterEcho,
    };
  }

  function stableEvidenceHash(value) {
    return (hashText(String(value)) >>> 0).toString(16).padStart(8, '0');
  }

  function canonicalApiOrderEvidence(order) {
    const items = (order.items || []).map((item) => ({
      itemId: String(item.itemId || ''),
      variantKey: String(item.variantKey || ''),
      variant: String(item.variant || ''),
      quantity: Number(item.quantity || 0),
      unitPrice: Number(item.unitPrice || 0),
      total: Number(item.total || 0),
    })).sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
    return {
      orderNumber: String(order.orderNumber || ''),
      orderDate: String(order.orderDate || ''),
      total: Number(order.total || 0),
      items,
    };
  }

  async function runOrdersApiCertifiedPass({
    exactDate,
    maxPages,
    scope,
    overrides = {},
  }) {
    const seenIds = new Set();
    const datesWithOrders = new Set();
    const targetOrders = new Map();
    const pageIdSets = [];
    const globalIdentity = [];
    let oldestObservedDate = '';
    let newestObservedDate = '';
    let previousCount = null;
    let filterEcho = 'absent';

    for (let page = 1; page <= maxPages; page += 1) {
      let response;
      try {
        response = await ordersApiFetchPage(page, overrides);
      } catch (error) {
        return {
          ok: false,
          reason: 'api-error',
          detail: `error en página ${page}: ${error && error.message ? error.message : error}`,
          pagesRead: page - 1,
          partialTargetCount: targetOrders.size,
        };
      }
      const state = ordersApiResponseState(response, scope, page);
      if (!state.ok) {
        return {
          ok: false,
          reason: state.reason,
          pagesRead: page,
          partialTargetCount: targetOrders.size,
        };
      }
      if (state.filterEcho === 'verified') filterEcho = 'verified';
      if (state.hasMore && state.orderKeys.length !== scope.pageSize) {
        return {
          ok: false,
          reason: 'inconsistent-page-size',
          pagesRead: page,
          partialTargetCount: targetOrders.size,
        };
      }

      const pageIds = [];
      for (const key of state.orderKeys) {
        const fields = state.modules[key] && state.modules[key].fields;
        const orderId = String(fields && fields.orderId || '').trim();
        const orderDate = parseApiOrderDate(fields && fields.orderDateText);
        if (!orderId || !orderDate) {
          return {
            ok: false,
            reason: 'invalid-order-identity',
            pagesRead: page,
            partialTargetCount: targetOrders.size,
          };
        }
        if (seenIds.has(orderId)) {
          return {
            ok: false,
            reason: 'feed-shifted',
            pagesRead: page,
            partialTargetCount: targetOrders.size,
          };
        }
        const order = mapApiOrder(fields);
        if (!order) {
          return {
            ok: false,
            reason: 'invalid-order-payload',
            pagesRead: page,
            partialTargetCount: targetOrders.size,
          };
        }
        seenIds.add(orderId);
        pageIds.push(orderId);
        globalIdentity.push(`${orderId}|${orderDate}`);
        datesWithOrders.add(orderDate);
        if (!oldestObservedDate || orderDate < oldestObservedDate) {
          oldestObservedDate = orderDate;
        }
        if (!newestObservedDate || orderDate > newestObservedDate) {
          newestObservedDate = orderDate;
        }
        if (orderDate === exactDate) targetOrders.set(orderId, order);
      }
      pageIdSets.push(pageIds.sort());

      if (!state.hasMore) {
        if (page === 1 && state.orderKeys.length === 0) {
          return {
            ok: false,
            reason: 'unavailable-empty-first-page',
            pagesRead: page,
            partialTargetCount: targetOrders.size,
          };
        }
        if (state.orderKeys.length === 0 && previousCount !== scope.pageSize) {
          return {
            ok: false,
            reason: 'inconsistent-empty-terminal',
            pagesRead: page,
            partialTargetCount: targetOrders.size,
          };
        }
        const targetEvidence = Array.from(targetOrders.values())
          .map(canonicalApiOrderEvidence)
          .sort((left, right) => left.orderNumber.localeCompare(right.orderNumber));
        return {
          ok: true,
          reason: 'has-more-false',
          pagesRead: page,
          terminalPage: page,
          targetOrders,
          datesWithOrders,
          oldestObservedDate,
          newestObservedDate,
          filterEcho,
          pageIdSets,
          globalIdentity: globalIdentity.sort(),
          targetEvidence,
        };
      }
      previousCount = state.orderKeys.length;
    }

    return {
      ok: false,
      reason: 'max-pages',
      pagesRead: maxPages,
      partialTargetCount: targetOrders.size,
    };
  }

  function certifiedPassEvidence(pass) {
    const pageIdSetHashes = pass.pageIdSets.map(
      (ids) => stableEvidenceHash(JSON.stringify(ids)),
    );
    return {
      pagesRead: pass.pagesRead,
      terminalPage: pass.terminalPage,
      uniqueOrderCount: pass.globalIdentity.length,
      targetOrderCount: pass.targetEvidence.length,
      filterEcho: pass.filterEcho,
      pageIdSetHashes,
      globalIdSetHash: stableEvidenceHash(JSON.stringify(pass.globalIdentity)),
      targetPayloadHash: stableEvidenceHash(JSON.stringify(pass.targetEvidence)),
    };
  }

  function certifiedPassesMatch(first, second) {
    return first.terminalPage === second.terminalPage &&
      JSON.stringify(first.pageIdSets) === JSON.stringify(second.pageIdSets) &&
      JSON.stringify(first.globalIdentity) === JSON.stringify(second.globalIdentity) &&
      JSON.stringify(first.targetEvidence) === JSON.stringify(second.targetEvidence);
  }

  async function collectCertifiedExactDate({ exactDate, maxPages }) {
    const scopeResult = ordersApiTemplateScope();
    const capturedAt = new Date().toISOString();
    if (!scopeResult.ok) {
      const reason = scopeResult.reason;
      const coverage = ordersApiCoverage({
        datesOnly: false,
        exactDate,
        maxPages,
        pagesRead: 0,
        reason,
      });
      coverage.mode = 'two-pass-v1';
      coverage.certified = false;
      coverage.scope = { capturedAt };
      coverage.targetDateComplete = false;
      return certifiedFailureResult({ exactDate, maxPages, coverage, reason });
    }
    const scope = scopeResult.scope;
    const first = await runOrdersApiCertifiedPass({ exactDate, maxPages, scope });
    if (!first.ok) {
      return certifiedFailureFromPass({ exactDate, maxPages, scope, capturedAt, pass: first });
    }
    const second = await runOrdersApiCertifiedPass({ exactDate, maxPages, scope });
    if (!second.ok) {
      return certifiedFailureFromPass({ exactDate, maxPages, scope, capturedAt, pass: second });
    }
    if (!certifiedPassesMatch(first, second)) {
      return certifiedFailureFromPass({
        exactDate,
        maxPages,
        scope,
        capturedAt,
        pass: {
          ok: false,
          reason: 'pass-drift',
          pagesRead: first.pagesRead + second.pagesRead,
          partialTargetCount: Math.max(
            first.targetEvidence.length,
            second.targetEvidence.length,
          ),
        },
        passes: [first, second],
      });
    }
    const scopeEvidence = {
      statusTab: scope.statusTab,
      timeOption: scope.timeOption,
      searchOption: scope.searchOption,
      capturedAt,
    };
    const termination = {
      kind: 'certified-has-more-false',
      reason: 'dos recorridos estables hasta hasMore=false',
      naturalExhaustion: true,
      hitPageLimit: false,
      pagesRead: first.pagesRead + second.pagesRead,
      pageLimit: maxPages,
      terminalPage: second.terminalPage,
    };
    const coverage = {
      mode: 'two-pass-v1',
      complete: true,
      partial: false,
      certified: true,
      targetDateComplete: true,
      pageLimit: maxPages,
      pagesRead: termination.pagesRead,
      observedFromDate: second.oldestObservedDate,
      observedToDate: second.newestObservedDate,
      stopReason: termination.kind,
      scope: scopeEvidence,
      termination,
    };
    const orders = Array.from(second.targetOrders.values());
    return {
      ok: true,
      orders,
      datesWithOrders: Array.from(second.datesWithOrders).sort(),
      pagesRead: termination.pagesRead,
      reason: termination.reason,
      warnings: [],
      partialOrderCount: 0,
      coverageComplete: true,
      coveragePartial: false,
      termination,
      coverage,
      certification: {
        certified: true,
        mode: 'two-pass-v1',
        scope: scopeEvidence,
        passCount: 2,
        passes: [certifiedPassEvidence(first), certifiedPassEvidence(second)],
        mismatchCodes: [],
      },
    };
  }

  function certifiedFailureFromPass({
    exactDate,
    maxPages,
    scope,
    capturedAt,
    pass,
    passes = [],
  }) {
    const reason = pass.detail || pass.reason;
    const coverage = ordersApiCoverage({
      datesOnly: false,
      exactDate,
      maxPages,
      pagesRead: pass.pagesRead || 0,
      reason: pass.reason,
    });
    coverage.mode = 'two-pass-v1';
    coverage.certified = false;
    coverage.scope = {
      statusTab: scope.statusTab,
      timeOption: scope.timeOption,
      searchOption: scope.searchOption,
      capturedAt,
    };
    coverage.targetDateComplete = false;
    return certifiedFailureResult({
      exactDate,
      maxPages,
      coverage,
      reason,
      partialTargetCount: pass.partialTargetCount || 0,
      passes,
      mismatchCode: pass.reason,
    });
  }

  function certifiedFailureResult({
    exactDate,
    maxPages,
    coverage,
    reason,
    partialTargetCount = 0,
    passes = [],
    mismatchCode = reason,
  }) {
    const warning = incompleteExactDateWarning(exactDate, {
      ...coverage,
      stopReason: reason || coverage.stopReason,
    });
    return {
      ok: false,
      orders: [],
      datesWithOrders: [],
      pagesRead: coverage.pagesRead || 0,
      reason,
      warnings: warning ? [warning] : [],
      partialOrderCount: partialTargetCount,
      coverageComplete: false,
      coveragePartial: true,
      termination: coverage.termination,
      coverage,
      certification: {
        certified: false,
        mode: 'two-pass-v1',
        scope: coverage.scope || {},
        passCount: passes.length,
        passes: passes.map(certifiedPassEvidence),
        mismatchCodes: mismatchCode ? [mismatchCode] : [],
      },
    };
  }

  async function ordersApiScopeProbe(options = {}) {
    const exactDate = String(options.exactDate || '').trim();
    const statusTab = String(options.statusTab || '').trim();
    const maxPages = Math.min(60, Math.max(1, Number(options.maxPages) || 60));
    if (!exactDate || !['recycle'].includes(statusTab) ||
        !captureOrdersApiTemplate() || !ordersApiAvailable()) {
      return { ok: false, reason: 'invalid-scope-probe' };
    }
    const overrides = { statusTab };
    const scopeResult = ordersApiTemplateScope(overrides);
    if (!scopeResult.ok) return { ok: false, reason: scopeResult.reason };
    const pass = await runOrdersApiCertifiedPass({
      exactDate,
      maxPages,
      scope: scopeResult.scope,
      overrides,
    });
    return {
      ok: pass.ok,
      reason: pass.reason,
      pagesRead: pass.pagesRead,
      targetDateCount: pass.ok
        ? pass.targetEvidence.length
        : (pass.partialTargetCount || 0),
      observedFromDate: pass.oldestObservedDate || '',
      observedToDate: pass.newestObservedDate || '',
      terminalPage: pass.terminalPage || null,
      filterEcho: pass.filterEcho || 'absent',
      scope: {
        statusTab: scopeResult.scope.statusTab,
        timeOption: scopeResult.scope.timeOption,
        searchOption: scopeResult.scope.searchOption,
        capturedAt: new Date().toISOString(),
      },
    };
  }

  function ordersApiCoverage({
    datesOnly,
    exactDate,
    maxPages,
    pagesRead,
    reason,
    oldestObservedDate = '',
    newestObservedDate = '',
  }) {
    // La API no es monotónica por fecha: sólo una página sin pedidos prueba
    // el final natural. Una o varias páginas antiguas no cierran una fecha
    // exacta porque AliExpress puede volver a entregar ese día más adelante.
    const termination = ordersApiTermination({ reason, pagesRead, maxPages });
    const historyComplete = termination.naturalExhaustion;
    return {
      mode: datesOnly ? 'dates-only' : (exactDate ? 'exact-date' : 'all-orders'),
      complete: historyComplete,
      partial: !historyComplete,
      targetDateComplete: exactDate ? historyComplete : null,
      pageLimit: maxPages,
      pagesRead,
      observedFromDate: oldestObservedDate,
      observedToDate: newestObservedDate,
      stopReason: reason,
      termination,
    };
  }

  function ordersApiTermination({ reason, pagesRead, maxPages }) {
    const naturalExhaustion = reason === 'sin más pedidos';
    const hitPageLimit = reason === 'max-pages';
    const kind = naturalExhaustion
      ? 'natural-exhaustion'
      : hitPageLimit
        ? 'max-pages'
        : reason === 'api-error' || String(reason || '').startsWith('error en página ')
          ? 'error'
          : 'unavailable';
    return {
      kind,
      reason,
      naturalExhaustion,
      hitPageLimit,
      pagesRead,
      pageLimit: maxPages,
    };
  }

  function incompleteExactDateWarning(exactDate, coverage) {
    if (!exactDate || coverage.targetDateComplete === true) return '';
    return `Cobertura incompleta para ${exactDate}: AliExpress terminó por `
      + `${coverage.stopReason || 'una causa desconocida'} tras `
      + `${coverage.pagesRead} de hasta ${coverage.pageLimit} páginas. `
      + 'No se generó una factura parcial.';
  }

  /// Recolecta pedidos página por página desde la API.
  ///
  /// Devuelve además el índice de días con pedidos: la misma pasada que busca
  /// un día sabe qué otros días tienen compras, y eso alimenta la marca del
  /// calendario sin una segunda consulta. `datesOnly: true` es un booleano
  /// estricto: recorre el índice sin construir los pedidos completos ni
  /// devolver sus líneas, montos o imágenes.
  /// @param {{exactDate?: string, maxPages?: number, datesOnly?: boolean}} options
  async function ordersApiCollect(options = {}) {
    const exactDate = String(options.exactDate || '').trim();
    const datesOnly = options.datesOnly === true;
    const evaluationOnly = options.evaluationOnly === true;
    const defaultMaxPages = exactDate ? 60 : 30;
    const maxPages = Math.min(
      60,
      Math.max(1, Number(options.maxPages) || defaultMaxPages),
    );
    if (!captureOrdersApiTemplate()) {
      const reason = 'sin plantilla de petición capturada';
      const coverage = ordersApiCoverage({
        datesOnly,
        exactDate,
        maxPages,
        pagesRead: 0,
        reason,
      });
      const warning = incompleteExactDateWarning(exactDate, coverage);
      return {
        ok: false,
        orders: [],
        datesWithOrders: [],
        pagesRead: 0,
        reason,
        warnings: warning ? [warning] : [],
        partialOrderCount: 0,
        coverageComplete: coverage.complete,
        coveragePartial: coverage.partial,
        termination: coverage.termination,
        coverage,
      };
    }
    if (!ordersApiAvailable()) {
      const reason = 'cliente de API no disponible en la página';
      const coverage = ordersApiCoverage({
        datesOnly,
        exactDate,
        maxPages,
        pagesRead: 0,
        reason,
      });
      const warning = incompleteExactDateWarning(exactDate, coverage);
      return {
        ok: false,
        orders: [],
        datesWithOrders: [],
        pagesRead: 0,
        reason,
        warnings: warning ? [warning] : [],
        partialOrderCount: 0,
        coverageComplete: coverage.complete,
        coveragePartial: coverage.partial,
        termination: coverage.termination,
        coverage,
      };
    }

    if (exactDate && !datesOnly && !evaluationOnly) {
      return collectCertifiedExactDate({ exactDate, maxPages });
    }

    const collected = new Map();
    const datesWithOrders = new Set();
    let pagesRead = 0;
    let reason = 'max-pages';
    let oldestObservedDate = '';
    let newestObservedDate = '';
    let discoveryOlderFrontierPages = 0;

    for (let page = 1; page <= maxPages; page += 1) {
      let response;
      try {
        response = await ordersApiFetchPage(page);
      } catch (error) {
        reason = `error en página ${page}: ${error && error.message ? error.message : error}`;
        break;
      }
      pagesRead = page;
      const modules = (response && response.data && response.data.data) || {};
      const orderKeys = Object.keys(modules)
        .filter((key) => /^pc_om_list_order_\d+$/.test(key));
      if (!orderKeys.length) {
        reason = 'sin más pedidos';
        break;
      }

      const pageDates = [];
      for (const key of orderKeys) {
        const fields = modules[key] && modules[key].fields;
        if (!fields || !fields.orderId) continue;
        // El modo de índice lee sólo identidad + fecha. En particular no
        // materializa líneas, importes, URLs ni imágenes de cada pedido.
        const order = datesOnly ? null : mapApiOrder(fields);
        const orderDate = datesOnly
          ? parseApiOrderDate(fields.orderDateText)
          : (order && order.orderDate) || '';
        if (!datesOnly && !order) continue;
        if (orderDate) {
          pageDates.push(orderDate);
          datesWithOrders.add(orderDate);
          if (!oldestObservedDate || orderDate < oldestObservedDate) {
            oldestObservedDate = orderDate;
          }
          if (!newestObservedDate || orderDate > newestObservedDate) {
            newestObservedDate = orderDate;
          }
        }
        if (!datesOnly && (!exactDate || orderDate === exactDate)) {
          collected.set(order.orderNumber, order);
        }
      }

      // A discovery run is deliberately not a completeness proof. Once it
      // has observed the requested day, five wholly older pages are enough to
      // stop paying the latency of walking years of an unstable offset feed.
      // Missing rows remain possible and the result stays non-certified; this
      // shortcut is never used by the production invoice path above.
      if (evaluationOnly && exactDate && collected.size > 0) {
        const whollyOlder = pageDates.length > 0 &&
          pageDates.every((value) => value < exactDate);
        discoveryOlderFrontierPages = whollyOlder
          ? discoveryOlderFrontierPages + 1
          : 0;
        if (discoveryOlderFrontierPages >= 5) {
          reason = 'discovery-frontier';
          break;
        }
      }
    }

    const coverage = ordersApiCoverage({
      datesOnly,
      exactDate,
      maxPages,
      pagesRead,
      reason,
      oldestObservedDate,
      newestObservedDate,
    });
    const collectedOrders = Array.from(collected.values());
    let warning = incompleteExactDateWarning(exactDate, coverage);
    const exactDateUsable = !exactDate || coverage.targetDateComplete === true;
    const discoveryUsable = evaluationOnly && Boolean(exactDate) &&
      collectedOrders.length > 0;
    if (discoveryUsable) {
      coverage.mode = 'discovery-read-only';
      coverage.certified = false;
      coverage.evaluationOnly = true;
      coverage.targetDateComplete = false;
      warning = `Lectura de diagnóstico incompleta para ${exactDate}: puede `
        + 'omitir pedidos y no autoriza guardar, vincular ni crear productos.';
    }
    return {
      ok: exactDateUsable || discoveryUsable,
      // Una fecha parcial se conserva sólo como conteo diagnóstico. No se
      // expone como factura utilizable. En debug, `evaluationOnly` habilita
      // únicamente la superficie OCR de lectura para medir filas observadas;
      // la cobertura sigue falsa y producción nunca solicita este modo.
      orders: exactDateUsable || discoveryUsable ? collectedOrders : [],
      datesWithOrders: Array.from(datesWithOrders).sort(),
      pagesRead,
      reason,
      warnings: warning ? [warning] : [],
      partialOrderCount: exactDateUsable ? 0 : collectedOrders.length,
      evaluationOnly: discoveryUsable,
      // Alias planos para hosts que sólo necesitan decidir si una ausencia
      // es concluyente; `coverage` conserva la evidencia detallada.
      coverageComplete: coverage.complete,
      coveragePartial: coverage.partial,
      termination: coverage.termination,
      coverage,
    };
  }

  // Sonda de forma: pide una página y describe cómo viene la respuesta, para
  // escribir el lector contra la estructura real y no contra una suposición.
  async function ordersApiShapeProbe() {
    if (!captureOrdersApiTemplate()) {
      return {
        ok: false,
        reason: 'sin plantilla de petición capturada',
        observedCalls: observedOrderApiCalls.length,
        probeInstalled: orderApiProbeInstalled,
      };
    }
    if (!ordersApiAvailable()) {
      return { ok: false, reason: 'window.lib.mtop no disponible' };
    }
    try {
      const response = await ordersApiFetchPage(1);
      return {
        ok: true,
        template: ordersApiTemplateSummary(),
        response: ordersApiResponseSummary(response),
      };
    } catch (error) {
      return {
        ok: false,
        reason: String(error && error.message ? error.message : error),
        template: ordersApiTemplateSummary(),
      };
    }
  }

  function ordersApiProbeRead() {
    const mtop = window.lib && window.lib.mtop;
    return {
      calls: observedOrderApiCalls.slice(0, 3),
      // Si la propia página expone su cliente MTOP, podemos pedirle los
      // pedidos por API sin reimplementar su firma de peticiones.
      hasLibMtop: Boolean(mtop && typeof mtop.request === 'function'),
      mtopKeys: mtop ? Object.keys(mtop).slice(0, 20) : [],
      hasH5Token: /(^|;\s*)_m_h5_tk=/.test(document.cookie || ''),
    };
  }

  // ── Pasos atómicos para un recorrido gobernado desde Dart ──────────────
  //
  // Por qué existe esta API: WebKit **suspende los timers de la página**
  // cuando la ventana de la app no está visible en macOS. El recorrido
  // original vivía dentro del WebView y esperaba con `setTimeout`, así que al
  // pasar la ventana a segundo plano el `await` no volvía nunca: el diálogo
  // quedaba girando para siempre y «revivía» al mirar la pantalla. Verificado
  // el 2026-08-06 con un latido `setInterval` que no emitió ni un solo tick
  // mientras la corrida estaba colgada.
  //
  // Con estos pasos, Dart pone el reloj (sus timers no dependen de la
  // visibilidad de la ventana) y cada llamada a JavaScript es corta y
  // síncrona. La página en segundo plano deja de ser un problema.
  // `precomputed` evita recalcular la lista tres veces por paso: detectar
  // tarjetas es la operación cara del recorrido y con la lista ya paginada
  // cada repetición se sentía en segundos por paso (2026-08-06).
  function ordersListStepState(precomputed) {
    const cards = precomputed ? precomputed.cards : collectOrderListCards();
    const loadMore = precomputed
      ? precomputed.loadMore
      : findOrdersListLoadMoreButton();
    let bottom = 0;
    for (const card of cards) {
      if (!card.getBoundingClientRect) continue;
      bottom = Math.max(bottom, card.getBoundingClientRect().bottom + window.scrollY);
    }
    if (loadMore && loadMore.getBoundingClientRect) {
      bottom = Math.max(bottom, loadMore.getBoundingClientRect().bottom + window.scrollY);
    }
    return {
      cards: cards.length,
      harvested: harvestedOrders.size,
      bottom,
      documentHeight: getDocumentScrollHeight(),
      scrollY: window.scrollY,
      viewportHeight: window.innerHeight || 800,
      hasLoadMore: Boolean(findOrdersListLoadMoreButton()),
      orderSignals: countOrderListNumbers(),
      domNodes: document.getElementsByTagName('*').length,
    };
  }

  function ordersListBeginSteppedRun() {
    harvestedOrders.clear();
    harvestedSignatures.clear();
    const prunedAtStart = startRecommendationPruning();
    harvestVisibleOrders();
    return { prunedAtStart, ...ordersListStepState() };
  }

  // Diagnóstico: qué controles hay al final de la lista. Sirve para saber
  // cómo se llama realmente el control de «más pedidos» en la variante de
  // AliExpress que está sirviendo la cuenta.
  function ordersListDebugTail() {
    const bottom = ordersRegionBottomY();
    const found = [];
    const nodes = document.querySelectorAll('button,[role="button"],a,span,div');
    for (const element of nodes) {
      if (found.length >= 30) break;
      if (!element.getBoundingClientRect) continue;
      const own = Array.from(element.childNodes)
        .filter((child) => child.nodeType === 3)
        .map((child) => child.nodeValue || '')
        .join(' ')
        .replace(/\s+/g, ' ')
        .trim();
      if (!own || own.length > 60) continue;
      const rect = element.getBoundingClientRect();
      const absoluteTop = rect.top + window.scrollY;
      // Sólo lo que está DEBAJO del final de la lista: ahí vive el control de
      // «más pedidos», sea botón, paginación numérica o enlace.
      if (absoluteTop < bottom - 60) continue;
      if (absoluteTop > bottom + 1400) continue;
      found.push({
        text: own,
        tag: element.tagName,
        top: Math.round(absoluteTop),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
      });
    }
    return { bottom: Math.round(bottom), candidates: found };
  }

  function ordersListScrollTo(y) {
    // Siempre un objeto: el puente de Dart sólo acepta mapas y un número
    // suelto aborta la corrida entera con «formato inesperado».
    window.scrollTo(window.scrollX, Math.max(0, Number(y) || 0));
    return { scrollY: window.scrollY };
  }

  function ordersListHarvestStep() {
    harvestVisibleOrders();
    return ordersListStepState({
      cards: collectOrderListCards(),
      loadMore: findOrdersListLoadMoreButton(),
    });
  }

  function ordersListClickLoadMore() {
    const button = findOrdersListLoadMoreButton();
    if (!button) return { clicked: false };
    button.scrollIntoView({ block: 'center', inline: 'nearest' });
    fireSyntheticClick(button);
    return { clicked: true };
  }

  function ordersListFinishSteppedRun(filters = {}) {
    stopRecommendationPruning();
    const harvested = Array.from(harvestedOrders.values());
    return {
      orders: harvested,
      diagnostics: diagnoseOrdersList(),
      reachedDate: ordersListHasReachedDate(filters.exactDate || filters.fromDate),
    };
  }

  // Poda del carrusel «More to love» mientras dura la extracción.
  //
  // Es la raíz del problema, no un síntoma: bajo la lista de pedidos vive un
  // carrusel de recomendaciones con scroll infinito. Cada pase de scroll le
  // añade cientos de nodos, el documento crece sin techo y todo lo demás
  // —contar pedidos, medir la lista, buscar el botón «ver más»— se vuelve
  // progresivamente más lento hasta que la extracción no termina nunca
  // (2026-08-06, el dueño lo vio en pantalla: «se salta el botón y sigue
  // bajando hasta productos sugeridos, cargando hasta el infinito»).
  //
  // Sólo se quitan nodos de la vista en memoria durante la recolección; no se
  // toca ningún dato del proveedor ni la sesión.
  let recommendationObserver = null;

  function pruneRecommendationSections() {
    let removed = 0;
    const body = document.body;
    if (!body) return 0;
    // Sólo secciones de primer nivel bajo body/main: el heading del carrusel
    // vive ahí. Nunca se sube más de lo necesario, para no llevarse la lista.
    const scan = Array.from(body.querySelectorAll('body > div, body > div > div, main > div, section'));
    for (const element of scan) {
      if (!element.isConnected) continue;
      const lead = normalizeText(element.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 160);
      if (!looksLikeRecommendationContainer(lead)) continue;
      element.remove();
      removed += 1;
    }
    return removed;
  }

  function startRecommendationPruning() {
    const initialRemoved = pruneRecommendationSections();
    if (recommendationObserver || typeof MutationObserver !== 'function') {
      return initialRemoved;
    }
    let scheduled = false;
    recommendationObserver = new MutationObserver(() => {
      if (scheduled) return;
      scheduled = true;
      // Agrupado: el carrusel inserta en ráfagas y podar por mutación
      // individual costaría más que el propio carrusel.
      window.setTimeout(() => {
        scheduled = false;
        pruneRecommendationSections();
      }, 250);
    });
    recommendationObserver.observe(document.body, { childList: true, subtree: true });
    return initialRemoved;
  }

  function stopRecommendationPruning() {
    if (!recommendationObserver) return;
    recommendationObserver.disconnect();
    recommendationObserver = null;
  }

  async function preloadOrdersListContent(filters = {}) {
    const initialX = window.scrollX;
    const initialY = window.scrollY;
    harvestedOrders.clear();
    harvestedSignatures.clear();
    // Latido independiente: distingue «JS atascado en algo síncrono» (el
    // latido sigue) de «el WebView congeló los timers» (el latido se detiene).
    let beat = 0;
    const heartbeat = window.setInterval(() => {
      beat += 1;
      aeDebug('list.heartbeat', { beat, at: Date.now() });
    }, 3000);
    const prunedAtStart = startRecommendationPruning();
    aeDebug('list.recommendations.pruned', {
      prunedAtStart,
      domNodes: document.getElementsByTagName('*').length,
    });
    harvestVisibleOrders();
    // Techo de tiempo del recorrido. Sin él, cualquier patología de la página
    // (carrusel infinito, tarjeta que no termina de montar, proceso de
    // contenido lento) deja el diálogo girando para siempre. Con él, el peor
    // caso entrega lo cosechado hasta ese momento y el flujo continúa.
    const deadline = Date.now() + 120000;
    const maxLoadClicks = Math.min(40, Math.max(0, Number(filters.maxLoadClicks) || 24));
    const maxScrollPasses = Math.max(8, maxLoadClicks + 8);
    let loadMoreClicks = 0;
    let scrollPasses = 0;
    let stuckClicks = 0;
    let noProgressPasses = 0;
    let terminationReason = 'max-scroll-passes';
    let lastTraversal = null;

    aeDebug('list.scroll.begin', {
      targetDate: filters.exactDate || filters.fromDate || '',
      maxLoadClicks,
      maxScrollPasses,
      initialOrderSignals: countOrderListNumbers(),
      initialHeight: getDocumentScrollHeight(),
    });

    for (let cycle = 0; cycle < maxScrollPasses; cycle += 1) {
      if (Date.now() > deadline) {
        terminationReason = 'deadline';
        aeDebug('list.scroll.deadline', {
          cycle: cycle + 1,
          harvested: harvestedOrders.size,
        });
        break;
      }
      const tCount = Date.now();
      const beforeCount = countOrderListNumbers();
      const tHeight = Date.now();
      // Altura de la LISTA, no del documento: las recomendaciones de abajo
      // crecen solas y hacían leer «hubo progreso» en cada pase, para siempre.
      const beforeHeight = ordersRegionBottomY();
      aeDebug('list.cycle.probe', {
        cycle: cycle + 1,
        countMs: tHeight - tCount,
        heightMs: Date.now() - tHeight,
        beforeCount,
        beforeHeight,
        domNodes: document.getElementsByTagName('*').length,
      });
      lastTraversal = await traverseLoadedOrdersList(initialX);
      scrollPasses += 1;
      harvestVisibleOrders();

      if (ordersListHasReachedDate(filters.exactDate || filters.fromDate)) {
        terminationReason = 'target-date-reached';
        aeDebug('list.scroll.cycle', {
          cycle: cycle + 1,
          beforeCount,
          afterCount: countOrderListNumbers(),
          beforeHeight,
          afterHeight: getDocumentScrollHeight(),
          loadMoreFound: Boolean(findOrdersListLoadMoreButton()),
          targetDateReached: true,
          traversal: lastTraversal,
        });
        break;
      }

      const loadMoreButton = findOrdersListLoadMoreButton();
      if (loadMoreButton && loadMoreClicks < maxLoadClicks) {
        loadMoreButton.scrollIntoView({ block: 'center', inline: 'nearest' });
        await sleep(160);
        fireSyntheticClick(loadMoreButton);
        loadMoreClicks += 1;
        await sleep(1100);
      } else if (lastTraversal && !lastTraversal.reachedBottom) {
        // Long order histories may span far more than one 9,000px pass. Keep
        // traversing even when the load-more control is still below the
        // viewport instead of stopping after the first chunk.
        terminationReason = 'continuing-long-list';
        continue;
      } else {
        // Newer AliExpress variants lazy-load at the bottom without rendering
        // a button. Give the list one more chance to append content — pero
        // hasta el fondo de la LISTA, nunca hasta el fondo del documento: ahí
        // abajo viven las recomendaciones de scroll infinito.
        window.scrollTo(
          initialX,
          Math.max(0, ordersRegionBottomY() - (window.innerHeight || 800) + 320),
        );
        await sleep(750);
      }

      const afterCount = countOrderListNumbers();
      const afterHeight = ordersRegionBottomY();
      aeDebug('list.scroll.cycle', {
        cycle: cycle + 1,
        beforeCount,
        afterCount,
        beforeHeight,
        afterHeight,
        loadMoreFound: Boolean(loadMoreButton),
        loadMoreClicks,
        noProgressPasses,
        traversal: lastTraversal,
      });
      if (afterCount <= beforeCount && afterHeight <= beforeHeight + 24) {
        noProgressPasses += 1;
        if (loadMoreButton) stuckClicks += 1;
        if (noProgressPasses >= 3 || stuckClicks >= 3) {
          terminationReason = loadMoreButton ? 'load-more-stuck' : 'end-of-list';
          break;
        }
      } else {
        noProgressPasses = 0;
        stuckClicks = 0;
      }

    }

    window.clearInterval(heartbeat);
    stopRecommendationPruning();
    const diagnostics = diagnoseOrdersList();
    window.scrollTo(initialX, initialY);
    await sleep(90);
    const result = {
      loadMoreClicks,
      scrollPasses,
      terminationReason,
      lastTraversal,
      ...diagnostics,
    };
    aeDebug('list.scroll.end', result);
    return result;
  }

  // Fondo real de la LISTA DE PEDIDOS (última tarjeta o botón «ver más»),
  // en coordenadas absolutas de documento.
  //
  // Por qué existe: bajo la lista, AliExpress monta un carrusel de productos
  // sugeridos con scroll infinito. Usar `document.scrollHeight` como destino
  // hacía que el recorrido pasara de largo el botón «ver más pedidos» —que al
  // salir de pantalla deja de ser clicable— y siguiera bajando por las
  // recomendaciones, que cargan sin fin: la extracción nunca terminaba
  // (2026-08-06, diagnosticado por el dueño mirando la pantalla).
  function ordersRegionBottomY() {
    let bottom = 0;
    const tCards = Date.now();
    const cards = collectOrderListCards();
    const tButton = Date.now();
    for (const card of cards) {
      if (!card.getBoundingClientRect) continue;
      bottom = Math.max(bottom, card.getBoundingClientRect().bottom + window.scrollY);
    }
    const loadMore = findOrdersListLoadMoreButton();
    aeDebug('list.region.probe', {
      cardsMs: tButton - tCards,
      buttonMs: Date.now() - tButton,
      cards: cards.length,
      foundLoadMore: Boolean(loadMore),
      bottom,
    });
    if (loadMore && loadMore.getBoundingClientRect) {
      bottom = Math.max(bottom, loadMore.getBoundingClientRect().bottom + window.scrollY);
    }
    return bottom;
  }

  async function traverseLoadedOrdersList(initialX) {
    // Un pase completo no debe poder secuestrar el recorrido entero.
    const traversalDeadline = Date.now() + 45000;
    const viewportHeight = window.innerHeight || 800;
    const documentMaxY = Math.max(0, getDocumentScrollHeight() - viewportHeight);
    // Techo: dejar visible el final de la lista más un margen para que el
    // botón «ver más pedidos» quede dentro de pantalla y sea clicable. Nunca
    // se entra en la zona de recomendaciones.
    const ordersMaxY = Math.max(0, ordersRegionBottomY() - viewportHeight + 320);
    const maxY = Math.min(documentMaxY, ordersMaxY);
    const startY = window.scrollY;
    const maxTraversalY = Math.min(maxY, startY + Math.max(9000, viewportHeight * 8));
    const step = Math.max(520, Math.floor(viewportHeight * 0.78));

    aeDebug('list.traverse.begin', {
      startY,
      maxY,
      documentMaxY,
      ordersMaxY,
      maxTraversalY,
      step,
      viewportHeight,
    });
    for (let y = startY; y <= maxTraversalY; y += step) {
      if (Date.now() > traversalDeadline) break;
      window.scrollTo(initialX, y);
      await sleep(150);
      aeDebug('list.traverse.step', {
        requestedY: y,
        actualY: window.scrollY,
        cards: collectOrderListCards().length,
      });
      // Cosechar en CADA paso: la lista virtualizada desmonta las tarjetas al
      // salir de la ventana visible, así que cosechar sólo al final del pase
      // pierde todo el tramo intermedio (v0.4.8 entregó 4 de 6 pedidos del
      // día objetivo por esto, 2026-08-05).
      harvestVisibleOrders();
    }
    window.scrollTo(initialX, maxTraversalY);
    await sleep(220);
    harvestVisibleOrders();
    return {
      harvestedOrders: Array.from(harvestedOrders.values()),
      startY,
      endY: window.scrollY,
      maxY,
      reachedBottom: maxTraversalY >= maxY - 12,
    };
  }

  function getDocumentScrollHeight() {
    return Math.max(
      document.documentElement ? document.documentElement.scrollHeight : 0,
      document.body ? document.body.scrollHeight : 0,
    );
  }

  function countOrderListNumbers() {
    // Acotado a la lista: `document.body.innerText` fuerza el layout completo
    // y devuelve el texto entero del documento; con las recomendaciones
    // cargadas eso son megabytes por llamada, y esta función corre en cada
    // ciclo del recorrido (2026-08-06).
    const countScope = ordersListScope();
    const host = countScope === document ? document.body : countScope;
    const text = normalizeText(host ? host.innerText : '');
    const numbers = new Set();
    const patterns = [
      /\border\s*(?:id|number|no\.?|#)?\s*[:#]?\s*(\d{8,})/gi,
      /\bpedido\s*(?:n[°ºo.]?|n[uú]mero|numero|id|#)?\s*[:#]?\s*(\d{8,})/gi,
      /\b(?:n[uú]mero|numero|n[°ºo.]?)\s+de\s+pedido\s*[:#]?\s*(\d{8,})/gi,
    ];
    patterns.forEach((pattern) => {
      let match;
      while ((match = pattern.exec(text)) !== null) numbers.add(match[1]);
    });
    Array.from(document.querySelectorAll('a[href]')).forEach((anchor) => {
      const orderNumber = extractOrderNumberFromHref(anchor.href || anchor.getAttribute('href') || '');
      if (orderNumber) numbers.add(orderNumber);
    });
    return numbers.size;
  }

  function ordersListHasReachedDate(fromDate) {
    const target = String(fromDate || '').trim();
    if (!target) return false;
    return collectOrderListCards().some((card) => {
      const text = normalizeText(card.innerText || card.textContent || '').trim();
      const date = extractOrderListDate(text.split('\n').map((line) => line.trim()).filter(Boolean));
      return date && date < target;
    });
  }

  // Elementos clicables cuyo TEXTO PROPIO dice «ver más pedidos» (o variante).
  // Recorre nodos de texto: lineal y sin forzar layout.
  function loadMoreTextCandidates(root) {
    const host = root === document ? document.body : root;
    if (!host) return [];
    if (typeof document.createTreeWalker !== 'function') {
      return Array.from(host.querySelectorAll('button,[role="button"],a,div,span'));
    }
    const walker = document.createTreeWalker(host, NodeFilter.SHOW_TEXT, null);
    const seen = new Set();
    const candidates = [];
    let node = walker.nextNode();
    while (node) {
      const value = node.nodeValue || '';
      if (value.length <= 80) {
        const compact = normalizeText(value).trim().toLowerCase().replace(/\s+/g, ' ');
        if (compact && loadMoreTextScore(compact)) {
          // El texto vive en un nodo hoja; el control clicable suele estar uno
          // o dos niveles arriba.
          let element = node.parentElement;
          for (let depth = 0; depth < 3 && element; depth += 1) {
            if (!seen.has(element)) {
              seen.add(element);
              candidates.push(element);
            }
            element = element.parentElement;
          }
        }
      }
      node = walker.nextNode();
    }
    return candidates;
  }

  function findOrdersListLoadMoreButton() {
    // Acotado a la región de la lista por la misma razón que
    // `collectOrderListCards`: barrer todo el documento con getComputedStyle
    // por nodo es inviable cuando las recomendaciones lo hacen crecer.
    // Desde el documento entero: el control de «más pedidos» queda FUERA del
    // contenedor de las tarjetas, y buscarlo dentro del ámbito memoizado lo
    // dejaba invisible (2026-08-06). Ya no es caro: el recorrido por nodos de
    // texto es lineal y sólo mira nodos cortos.
    const root = document;
    // Candidatos por NODO DE TEXTO, no por elemento: leer `textContent` de
    // cada div/span del documento es cuadrático (cada ancestro reconcatena el
    // texto de su subárbol) y con el carrusel de recomendaciones cargado eso
    // tarda minutos — era el punto exacto donde la extracción se congelaba
    // (2026-08-06). Sólo un puñado de nodos dice «ver más»; nadie más paga.
    const textualCandidates = loadMoreTextCandidates(root);
    return textualCandidates
      .map((element) => ({ element, score: ordersListLoadMoreScore(element) }))
      .filter((entry) => entry.score > 0)
      .sort((a, b) => b.score - a.score)[0]?.element || null;
  }

  function ordersListLoadMoreScore(element) {
    if (!element || !element.getBoundingClientRect) return 0;
    const text = normalizeText(element.innerText || element.textContent || element.getAttribute('aria-label') || '').trim();
    const compact = text.toLowerCase().replace(/\s+/g, ' ');
    if (!compact || compact.length > 80) return 0;
    if (/order\s*details|detalles\s+del\s+pedido|add\s+to\s+cart|remove|copy|need\s+help/i.test(compact)) return 0;
    if (!loadMoreTextScore(compact)) return 0;

    const rect = element.getBoundingClientRect();
    const style = window.getComputedStyle ? window.getComputedStyle(element) : null;
    // Sin exigir cercanía al viewport: el control de «más pedidos» vive bajo
    // el final de la lista, muy por debajo de la pantalla cuando se lo busca
    // desde arriba, y descartarlo por lejanía lo volvía invisible para todo el
    // recorrido —la importación se quedaba con la primera página de pedidos—
    // (2026-08-06; en esta cuenta el control se rotula «View orders»). Quien
    // decide cuándo hacer scroll es el recorrido, no el detector.
    if (rect.width < 60 || rect.height < 20) return 0;
    if (style && (style.display === 'none' || style.visibility === 'hidden' || style.pointerEvents === 'none')) return 0;
    if (element.disabled || element.getAttribute('aria-disabled') === 'true') return 0;
    if (hasFloatingUiAncestor(element) || hasRecommendationAncestor(element)) return 0;

    let score = loadMoreTextScore(compact);
    if (!score) return 0;
    score += Math.max(0, rect.top + window.scrollY) / 100000;
    if (element.matches('button,[role="button"],a')) score += 5;
    return score;
  }

  function loadMoreTextScore(value) {
    const compact = normalizeText(value).trim().toLowerCase().replace(/\s+/g, ' ');
    if (!compact || compact.length > 80) return 0;
    if (/^(view|show|load|see)\s+(?:\d+\s+)?(?:more\s+)?orders?(?:\s*[([]\d+[)\]])?$/.test(compact)) return 100;
    if (/^(view|show|load|see)\s+more(?:\s*[([]\d+[)\]])?$/.test(compact)) return 75;
    if (/^(ver|mostrar|cargar)\s+(?:m[aá]s\s+)?(?:pedidos|[oó]rdenes)(?:\s*[([]\d+[)\]])?$/.test(compact)) return 100;
    if (/^(ver|mostrar|cargar)\s+m[aá]s(?:\s*[([]\d+[)\]])?$/.test(compact)) return 75;
    return 0;
  }

  function sleep(milliseconds) {
    return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
  }

  function extractOrder() {
    const text = normalizeText(document.body ? document.body.innerText : '');
    const orderScope = buildOrderScope(text);
    const scopedLines = orderScope.text.split('\n').map((line) => line.trim()).filter(Boolean);
    const fullLines = text.split('\n').map((line) => line.trim()).filter(Boolean);
    const orderNumber = extractOrderNumber(scopedLines) || extractOrderNumber(fullLines) || extractOrderNumberFromUrl();
    const orderDate = extractDate(scopedLines);
    const totals = extractTotals(scopedLines);
    const mediaItems = collectOrderMedia(orderScope);
    const items = extractItems(totals.currency, orderScope, mediaItems);
    const warnings = [];

    if (!orderNumber) warnings.push('No se encontro numero de pedido. Revisalo manualmente.');
    if (!orderDate) warnings.push('No se encontro fecha de compra confiable. Evite usar la fecha estimada de entrega como fecha de factura.');
    if (!totals.total) warnings.push('No se encontro total. Revisalo manualmente.');
    if (items.length === 0) warnings.push('No se encontraron productos visibles; se creo una linea resumen.');

    const resolvedItems = items.length > 0
      ? items
      : [{
          sku: orderNumber ? `AE-${lastDigits(orderNumber, 8)}` : 'AE-ORDER',
          lineTitle: orderNumber ? `AliExpress order ${orderNumber}` : 'AliExpress order',
          description: orderNumber ? `AliExpress order ${orderNumber}` : 'AliExpress order',
          variant: '',
          quantity: 1,
          unitPrice: totals.total || 0,
          total: totals.total || 0,
          productUrl: location.href,
          itemId: '',
          imageUrl: '',
        }];

    return {
      source: SOURCE,
      pageUrl: location.href,
      pageTitle: document.title || '',
      extractedAt: new Date().toISOString(),
      supplierName: 'AliExpress Marketplace',
      supplierTaxId: '',
      orderNumber: orderNumber || '',
      orderDate: orderDate || '',
      currency: 'CLP',
      subtotal: totals.subtotal || null,
      shipping: totals.shipping || null,
      tax: totals.tax || null,
      discount: totals.discount || null,
      total: totals.total || sumItems(resolvedItems),
      __authoritativeTotals: totals.__authoritative === true,
      items: resolvedItems,
      media: mediaItems.map((media) => ({
        sku: media.itemId ? `AE-${lastDigits(media.itemId, 8)}` : '',
        imageUrl: media.imageUrl || '',
        productUrl: media.productUrl || '',
        itemId: media.itemId || '',
        title: media.title || '',
      })),
      notes: buildDefaultNotes(orderNumber),
      warnings,
      rawTextPreview: orderScope.text.slice(0, 5000),
      __expandDebug: globalThis.__AE_EXPAND_DEBUG__ || null,
    };
  }

  function extractOrdersList(filters = {}) {
    const exactDate = String(filters.exactDate || '').trim();
    const dateMode = (exactDate || filters.dateMode === 'day') ? 'day' : 'range';
    const fromDate = exactDate || String(filters.fromDate || '').trim();
    const toDate = exactDate || String(filters.toDate || '').trim();
    const warnings = [];
    const cards = collectOrderListCards();
    const allOrders = cards
      .map(buildOrderListInvoice)
      .filter(Boolean);
    const dateFilterActive = Boolean(fromDate || toDate);
    const orders = allOrders
      .filter((order) => isDateInRange(order.orderDate, fromDate, toDate, dateFilterActive));
    const undatedCount = allOrders.filter((order) => !order.orderDate).length;

    if (cards.length === 0) {
      warnings.push('No se encontraron tarjetas de orden en la lista actual. Abre Account > Orders y deja cargadas las ordenes visibles.');
    }
    if (cards.length > 0 && orders.length === 0) {
      warnings.push('Se encontraron ordenes, pero ninguna calza con el rango de fechas seleccionado.');
    }
    if (undatedCount > 0) {
      warnings.push(dateFilterActive
        ? `${undatedCount} orden(es) no tenian fecha de compra parseable en la lista y se omitieron por el filtro de fecha.`
        : `${undatedCount} orden(es) no tenian fecha de compra parseable en la lista; se incluyeron para revision manual.`);
    }

    return {
      pageUrl: location.href,
      pageTitle: document.title || '',
      collectedAt: new Date().toISOString(),
      dateMode,
      exactDate,
      fromDate,
      toDate,
      scannedCount: cards.length,
      orders,
      warnings,
    };
  }

  // Raíz del listado de pedidos, memoizada.
  //
  // Por qué: escanear `document` entero leyendo `innerText` de cada div fuerza
  // un reflow por nodo. Con el carrusel de recomendaciones (scroll infinito)
  // el documento llega a decenas de miles de nodos y una sola pasada tarda
  // minutos — con la cosecha por paso de scroll, la extracción no terminaba
  // nunca (2026-08-06). Acotado al contenedor de la lista, el costo es
  // constante por pase aunque las recomendaciones sigan creciendo.
  let cachedOrdersListRoot = null;
  let lastReportedCardCount = -1;
  const ORDER_NUMBER_LABEL_PATTERN =
    /ref\.?\s*number|n[uú]mero\s+de\s+pedido|order\s*(?:id|number|no)|pedido\s*[:#]/i;

  function ordersListScope() {
    if (cachedOrdersListRoot && cachedOrdersListRoot.isConnected) {
      return cachedOrdersListRoot;
    }
    cachedOrdersListRoot = null;
    return document;
  }

  function rememberOrdersListRoot(cards) {
    if (!cards.length || cachedOrdersListRoot) return;
    let root = cards[0].parentElement;
    while (root && root !== document.body) {
      if (cards.every((card) => root.contains(card))) break;
      root = root.parentElement;
    }
    // `body` no acota nada: si el ancestro común es el body, no cacheamos y
    // seguimos escaneando el documento (con el filtro barato de textContent).
    if (root && root !== document.body && root.querySelectorAll) {
      cachedOrdersListRoot = root;
    }
  }

  // Elementos que contienen literalmente un número de pedido.
  //
  // Recorre NODOS DE TEXTO, no elementos: leer `textContent`/`innerText` de
  // cada div anidado es cuadrático (cada ancestro reconcatena el texto de
  // todos sus hijos) y `innerText` además fuerza layout. Con el carrusel de
  // recomendaciones inflando el documento, ese barrido tardaba minutos y la
  // extracción no terminaba nunca (2026-08-06). El TreeWalker es lineal y no
  // toca el layout; sólo los pocos elementos que ya contienen el número pagan
  // el `innerText` posterior.
  function orderNumberSeedElements(scope) {
    const root = scope === document ? document.body : scope;
    if (!root) return [];
    if (typeof document.createTreeWalker !== 'function') {
      // Entornos de prueba sin TreeWalker: camino anterior, acotado.
      return Array.from(root.querySelectorAll('article,section,li,div'));
    }
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    const seen = new Set();
    const elements = [];
    let node = walker.nextNode();
    while (node) {
      const value = node.nodeValue || '';
      if (value.length < 240 && ORDER_NUMBER_LABEL_PATTERN.test(value)) {
        // Subir unos niveles: el número vive en un nodo hoja, la tarjeta está
        // más arriba. `findOrderListCard` termina de resolverla.
        let element = node.parentElement;
        for (let depth = 0; depth < 3 && element; depth += 1) {
          if (!seen.has(element)) {
            seen.add(element);
            elements.push(element);
          }
          element = element.parentElement;
        }
      }
      node = walker.nextNode();
    }
    return elements;
  }

  function collectOrderListCards() {
    const byOrder = new Map();
    const seeds = new Set();
    const scope = ordersListScope();
    for (const element of orderNumberSeedElements(scope)) {
      if (!element || !element.getBoundingClientRect) continue;
      const text = normalizeText(element.innerText || element.textContent || '').trim();
      if (!text || text.length < 16 || text.length > 1800) continue;
      if (extractOrderListNumber(text)) seeds.add(element);
    }
    Array.from(scope.querySelectorAll('a[href]')).forEach((anchor) => {
      if (extractOrderNumberFromHref(anchor.href || anchor.getAttribute('href') || '')) {
        seeds.add(anchor);
      }
    });

    seeds.forEach((element) => {
      const seedOrderNumber = extractOrderListNumberFromElement(element);
      if (!seedOrderNumber) return;
      const card = findOrderListCard(element, seedOrderNumber);
      if (!card) return;
      // One card may contain product/store links with unrelated numeric IDs.
      // Always key the result by the canonical order number resolved from the
      // complete card, never by the seed link that happened to find it.
      const orderNumber = extractOrderListNumberFromElement(card);
      if (!orderNumber) return;
      const cardText = normalizeText(card.innerText || card.textContent || '').trim();
      const candidate = { element: card, text: cardText, orderNumber, score: orderListCardScore(card, cardText) };
      const existing = byOrder.get(orderNumber);
      if (!existing || candidate.score > existing.score) byOrder.set(orderNumber, candidate);
    });

    const selected = Array.from(byOrder.values())
      .sort((a, b) => cardPageY(a.element) - cardPageY(b.element))
      .map((entry) => entry.element);
    rememberOrdersListRoot(selected);
    // La detección corre en cada paso de scroll: emitir el detalle completo
    // por paso inunda el log y ralentiza el puente. Se registra una vez por
    // conteo distinto.
    if (selected.length !== lastReportedCardCount) {
      lastReportedCardCount = selected.length;
      aeDebug('list.cards.detected', {
        seedCount: seeds.size,
        uniqueOrderCount: byOrder.size,
        scoped: cachedOrdersListRoot != null,
        selected: Array.from(byOrder.values()).map((entry) => ({
          orderNumber: entry.orderNumber,
          score: roundMoney(entry.score),
          textLength: entry.text.length,
        })),
      });
    }
    return selected;
  }

  function findOrderListCard(seed, orderNumber) {
    let current = seed;
    let best = null;
    let bestScore = Number.NEGATIVE_INFINITY;
    for (let depth = 0; depth < 12 && current && current !== document.body; depth += 1) {
      if (!current.getBoundingClientRect) {
        current = current.parentElement;
        continue;
      }
      const rect = current.getBoundingClientRect();
      const text = normalizeText(current.innerText || current.textContent || '').trim();
      const lines = text.split('\n').map((line) => line.trim()).filter(Boolean);
      const containsOrder = elementContainsOrderNumber(current, orderNumber);
      const date = extractOrderListDate(lines);
      const hasTotal = Boolean(extractOrderListTotal(lines, text));
      const hasProduct = Boolean(current.querySelector && current.querySelector(
        'a[href*="/item/"],a[href*="itemId="],a[href*="productId="],img[src],img[data-src]',
      ));
      const hasDetailLink = Array.from(current.querySelectorAll ? current.querySelectorAll('a[href]') : [])
        .some((anchor) => extractOrderNumberFromHref(anchor.href || anchor.getAttribute('href') || '') === orderNumber);
      const reasonable = rect.width >= 280 && rect.height >= 55 && text.length <= 8000;
      if (containsOrder && date && (hasTotal || hasProduct || hasDetailLink) && reasonable && !isRecommendationText(text)) {
        const score = orderListCardScore(current, text)
          + (hasTotal ? 35 : 0)
          + (hasProduct ? 25 : 0)
          + (hasDetailLink ? 20 : 0)
          - Math.max(0, text.length - 2600) / 40
          - Math.max(0, rect.height - 900) / 15;
        if (score > bestScore) {
          best = current;
          bestScore = score;
        }
      }
      current = current.parentElement;
    }
    return best;
  }

  function extractOrderListNumberFromElement(element) {
    if (!element) return '';
    const text = normalizeText(element.innerText || element.textContent || '').trim();
    const fromText = extractOrderListNumber(text);
    if (fromText) return fromText;

    const links = [];
    if (element.matches && element.matches('a[href]')) links.push(element);
    if (element.querySelectorAll) links.push(...Array.from(element.querySelectorAll('a[href]')));
    for (const link of links) {
      const fromHref = extractOrderNumberFromHref(link.href || link.getAttribute('href') || '');
      if (fromHref) return fromHref;
    }

    const attributes = ['data-order-id', 'data-order-number', 'data-order-no', 'data-orderid'];
    for (const name of attributes) {
      const value = element.getAttribute && element.getAttribute(name);
      const match = String(value || '').match(/\d{8,}/);
      if (match) return match[0];
    }
    return '';
  }

  function elementContainsOrderNumber(element, orderNumber) {
    if (!element || !orderNumber) return false;
    const text = normalizeText(element.innerText || element.textContent || '');
    if (text.includes(orderNumber)) return true;
    if (!element.querySelectorAll) return false;
    return Array.from(element.querySelectorAll('a[href]')).some((anchor) =>
      extractOrderNumberFromHref(anchor.href || anchor.getAttribute('href') || '') === orderNumber
    );
  }

  function diagnoseOrdersList() {
    const cards = collectOrderListCards();
    const dates = cards
      .map((card) => extractOrderListDate(
        normalizeText(card.innerText || card.textContent || '')
          .split('\n')
          .map((line) => line.trim())
          .filter(Boolean),
      ))
      .filter(Boolean)
      .sort();
    const loadMore = findOrdersListLoadMoreButton();
    return {
      visibleOrderSignals: countOrderListNumbers(),
      detectedCards: cards.length,
      datedCards: dates.length,
      oldestVisibleDate: dates[0] || '',
      newestVisibleDate: dates[dates.length - 1] || '',
      loadMoreFound: Boolean(loadMore),
      loadMoreLabel: loadMore
        ? normalizeText(loadMore.innerText || loadMore.textContent || loadMore.getAttribute('aria-label') || '')
            .trim()
            .slice(0, 80)
        : '',
      documentHeight: getDocumentScrollHeight(),
      finalScrollY: window.scrollY,
    };
  }

  function orderListCardScore(card, text) {
    const rect = card.getBoundingClientRect ? card.getBoundingClientRect() : { width: 0, height: 0 };
    let score = 0;
    if (/\border\s*details\b|\bdetalles\s+del\s+pedido\b/i.test(text)) score += 50;
    if (/\bcompleted\b|\bprocesado\b|\bcompletado\b/i.test(text)) score += 10;
    if (extractOrderListItems(card).length > 0) score += 40;
    score += Math.min(rect.width, 1200) / 50;
    score += Math.min(rect.height, 500) / 20;
    score -= Math.max(0, text.length - 1800) / 100;
    return score;
  }

  function cardPageY(card) {
    const rect = card && card.getBoundingClientRect ? card.getBoundingClientRect() : { top: 0 };
    return rect.top + window.scrollY;
  }

  function buildOrderListInvoice(card) {
    const text = normalizeText(card.innerText || card.textContent || '').trim();
    const lines = text.split('\n').map((line) => line.trim()).filter(Boolean);
    const orderNumber = extractOrderListNumberFromElement(card);
    if (!orderNumber) return null;

    const orderDate = extractOrderListDate(lines);
    const totalMoney = extractOrderListTotal(lines, text);
    const detailUrl = findOrderListDetailUrl(card, orderNumber) || location.href;
    const items = extractOrderListItems(card);
    const resolvedItems = items.length > 0 ? items : [buildOrderListSummaryItem(card, orderNumber, totalMoney)];
    const total = totalMoney ? totalMoney.amount : sumItems(resolvedItems);

    const invoice = {
      source: SOURCE,
      generatedAt: new Date().toISOString(),
      extractedAt: new Date().toISOString(),
      pageUrl: detailUrl,
      pageTitle: document.title || '',
      supplierName: 'AliExpress Marketplace',
      supplierTaxId: '',
      orderNumber,
      orderDate: orderDate || '',
      currency: totalMoney ? (totalMoney.currency || 'CLP') : 'CLP',
      subtotal: total,
      shipping: null,
      tax: null,
      discount: null,
      total,
      notes: [
        'Documento generado desde lista de ordenes AliExpress.',
        `Pedido AliExpress: ${orderNumber}.`,
        detailUrl ? `URL: ${detailUrl}` : '',
      ].filter(Boolean).join('\n'),
      items: resolvedItems,
      warnings: [
        'Orden extraida desde lista; si necesitas shipping/subtotal exacto, abre el detalle y usa Extraer.',
        orderDate ? '' : 'No se pudo leer la fecha de compra desde la lista; verifica el detalle antes de contabilizar.',
      ].filter(Boolean),
      listTextPreview: text.slice(0, 1200),
    };
    aeDebug('list.card.extracted', {
      ...debugOrderSummary(invoice),
      detailUrlKind: /\/p\/message\//i.test(detailUrl)
        ? 'message'
        : /order.*detail|detail.*order/i.test(detailUrl)
          ? 'order-detail'
          : 'other',
      usedSummaryPlaceholder: items.length === 0,
    });
    return invoice;
  }

  function extractOrderListNumber(text) {
    const patterns = [
      /\b(?:order|purchase)\s*(?:id|number|no\.?|#)?\s*[:#]?\s*(\d{8,})/i,
      /\bpedido\s*(?:n[°ºo.]?|n[uú]mero|numero|id|#)?\s*[:#]?\s*(\d{8,})/i,
      /\b(?:n[uú]mero|numero|n[°ºo.]?)\s+de\s+pedido\s*[:#]?\s*(\d{8,})/i,
    ];
    for (const pattern of patterns) {
      const match = String(text || '').match(pattern);
      if (match) return match[1];
    }
    return '';
  }

  function extractOrderListDate(lines) {
    const dateLabel = /\b(?:order\s*(?:date|placed)|placed\s+on|purchase\s+date|date\s+purchased|fecha\s*(?:del\s*)?(?:pedido|compra)|comprado\s+el|pedido\s+(?:efectuado|realizado)(?:\s+el)?)\b/i;
    const dateLine = lines.find((line) => dateLabel.test(line) && !isDeliveryDateLine(line));
    if (dateLine) {
      const afterLabel = dateLine.replace(
        /^.*?(?:order\s*(?:date|placed)|placed\s+on|purchase\s+date|date\s+purchased|fecha\s*(?:del\s*)?(?:pedido|compra)|comprado\s+el|pedido\s+(?:efectuado|realizado)(?:\s+el)?)\s*[:\-]?\s*/i,
        '',
      );
      return parseDateString(afterLabel) || parseDateString(dateLine);
    }
    return extractDate(lines);
  }

  function extractOrderNumberFromHref(value) {
    const raw = String(value || '').trim();
    if (!raw) return '';
    try {
      const base = globalThis.location && globalThis.location.href
        ? globalThis.location.href
        : 'https://www.aliexpress.com/';
      const url = new URL(raw, base);
      const keys = [
        'orderId',
        'orderIdList',
        'orderNo',
        'orderNoList',
        'orderNumber',
        'order_id',
        'order_no',
      ];
      for (const key of keys) {
        const candidate = url.searchParams.get(key);
        const match = String(candidate || '').match(/\d{8,}/);
        if (match) return match[0];
      }

      const decoded = decodeURIComponent(`${url.pathname}${url.hash}`);
      const labeled = decoded.match(/(?:order|detail)[^\d]{0,32}(\d{8,})/i);
      if (labeled) return labeled[1];
      // Never treat generic numeric paths (for example /store/1103059752) as
      // order IDs. A bare path number is valid only inside an order-detail URL.
      const hasOrderPathContext = /(?:^|\/)(?:p\/)?order(?:\/|[-_])|order.*detail|detail.*order/i.test(decoded);
      const pathNumber = hasOrderPathContext
        ? decoded.match(/(?:^|[\/_-])(\d{10,})(?:[\/_-]|$)/)
        : null;
      return pathNumber ? pathNumber[1] : '';
    } catch (_error) {
      const fallback = raw.match(/(?:order(?:Id|No|Number)?|pedido)[^\d]{0,20}(\d{8,})/i);
      return fallback ? fallback[1] : '';
    }
  }

  function extractOrderListTotal(lines, text) {
    const totalLine = lines.find((line) => /\btotal\s*:/i.test(line))
      || lines.find((line) => /\btotal\b/i.test(line) && extractMoneyTokens(line).length > 0);
    return parseBestMoney(totalLine || text);
  }

  function findOrderListDetailUrl(card, orderNumber) {
    const anchors = Array.from(card.querySelectorAll('a[href]'));
    const detailAnchor = anchors.find((anchor) => isUsableOrderDetailHref(
      anchor.href || anchor.getAttribute('href') || '',
      orderNumber,
    ));
    if (detailAnchor && detailAnchor.href) return detailAnchor.href;

    const digits = String(orderNumber || '').replace(/\D+/g, '');
    if (!digits) return '';
    const base = globalThis.location && globalThis.location.href
      ? globalThis.location.href
      : 'https://www.aliexpress.com/';
    return new URL(`/p/order/detail.html?orderId=${encodeURIComponent(digits)}`, base).toString();
  }

  function isUsableOrderDetailHref(value, orderNumber) {
    try {
      const base = globalThis.location && globalThis.location.href
        ? globalThis.location.href
        : 'https://www.aliexpress.com/';
      const url = new URL(String(value || ''), base);
      const path = url.pathname.toLowerCase();
      if (/\/p\/message\//i.test(path) || /\/p\/order\/index\.html/i.test(path)) return false;
      if (!(path.includes('order') && path.includes('detail'))) return false;
      const expected = String(orderNumber || '').replace(/\D+/g, '');
      const resolved = extractOrderNumberFromHref(url.toString());
      return !expected || !resolved || resolved === expected;
    } catch (_) {
      return false;
    }
  }

  function extractOrderListItems(card) {
    const rowCandidates = collectOrderListProductRows(card)
      .map((row) => buildOrderListItemFromRow(card, row))
      .filter(Boolean);
    const mediaCandidates = collectCandidateImageElements(card)
      .map((element) => buildOrderListItemFromMedia(card, element))
      .filter(Boolean);
    const candidates = [...rowCandidates, ...mediaCandidates];
    if (candidates.length === 0) return [];
    return collapseOrderListItemCandidates(candidates);
  }

  function collapseOrderListItemCandidates(candidates) {
    const publicItems = [...(candidates || [])]
      .sort((a, b) => Number(a._y || 0) - Number(b._y || 0) || Number(a._x || 0) - Number(b._x || 0))
      .map((item) => {
        const { _y, _x, ...publicItem } = item;
        return publicItem;
      });
    return dedupeExtractedItems(publicItems).slice(0, 20);
  }

  function collectOrderListProductRows(card) {
    const rows = new Set();
    Array.from(card.querySelectorAll('a[href*="/item/"],a[href*="itemId="],a[href*="productId="]'))
      .forEach((anchor) => {
        const row = findCompactOrderListItemRow(card, anchor);
        if (row) rows.add(row);
      });
    collectCandidateImageElements(card).forEach((image) => {
      const row = findCompactOrderListItemRow(card, image);
      if (row) rows.add(row);
    });
    Array.from(card.querySelectorAll('li,article,section,div')).forEach((element) => {
      if (element === card || !element.getBoundingClientRect) return;
      if (isLikelyOrderListProductRow(element)) rows.add(element);
    });

    return Array.from(rows)
      .filter((row) => !Array.from(rows).some((other) => other !== row && row.contains(other) && compactProductRowScore(other) >= compactProductRowScore(row)))
      .sort((a, b) => cardPageY(a) - cardPageY(b));
  }

  function findCompactOrderListItemRow(card, seed) {
    let current = seed;
    let best = null;
    for (let depth = 0; depth < 8 && current && current !== card && current !== document.body; depth += 1) {
      if (isLikelyOrderListProductRow(current)) best = current;
      current = current.parentElement;
    }
    return best;
  }

  function isLikelyOrderListProductRow(element) {
    if (!element || !element.getBoundingClientRect) return false;
    const rect = element.getBoundingClientRect();
    const text = normalizeText(element.innerText || element.textContent || '').trim();
    if (!text || text.length < 20 || text.length > 1200) return false;
    if (rect.width < 220 || rect.height < 36 || rect.height > 260) return false;
    if (isPageChromeContainer(text) || isRecommendationText(text)) return false;
    if (/\border\s*date\b|\border\s*id\b|\border\s*details\b|\badd\s+to\s+cart\b|\bremove\b|\bcopy\b/i.test(text) && text.length > 350) return false;

    const hasProductLink = Boolean(findLocalProductUrlInRow(element));
    const hasImage = collectCandidateImageElements(element).some((image) => {
      const imageRect = image.getBoundingClientRect ? image.getBoundingClientRect() : { width: 0, height: 0 };
      return imageUrlFromElement(image) && imageRect.width >= 24 && imageRect.height >= 24;
    });
    const hasTitle = Boolean(titleFromNearbyText(text) || readFirstText(element, ['a[href*="/item/"]', 'a[href*="itemId="]', 'a[href*="productId="]', '[title]']));
    const hasMoneyOrQuantity = extractMoneyTokens(text).length > 0 || /(?:^|\s)[x×]\s*\d+(?:\.\d+)?\b/i.test(text);
    return (hasProductLink || hasImage) && hasTitle && hasMoneyOrQuantity;
  }

  function compactProductRowScore(row) {
    if (!row || !row.getBoundingClientRect) return 0;
    const rect = row.getBoundingClientRect();
    const text = normalizeText(row.innerText || row.textContent || '').trim();
    let score = 0;
    if (findLocalProductUrlInRow(row)) score += 30;
    if (pickPrimaryRowImage(row)) score += 20;
    if (titleFromNearbyText(text)) score += 20;
    if (extractMoneyTokens(text).length > 0) score += 10;
    score -= Math.max(0, text.length - 500) / 25;
    score -= Math.max(0, rect.height - 150) / 10;
    return score;
  }

  function buildOrderListItemFromRow(card, row) {
    if (!row || !row.getBoundingClientRect) return null;
    const rect = row.getBoundingClientRect();
    const imageUrl = pickPrimaryRowImage(row);
    return buildOrderListItemFromContext(card, row, row, imageUrl, rect);
  }

  function buildOrderListItemFromMedia(card, mediaElement) {
    if (!mediaElement || !mediaElement.getBoundingClientRect) return null;
    const rect = mediaElement.getBoundingClientRect();
    const imageUrl = imageUrlFromElement(mediaElement);
    if (!imageUrl || rect.width < 24 || rect.height < 24) return null;
    if (hasFloatingUiAncestor(mediaElement) || hasRecommendationAncestor(mediaElement)) return null;

    const row = findOrderListItemRow(card, mediaElement);
    if (!row) return null;
    return buildOrderListItemFromContext(card, row, mediaElement, imageUrl, rect);
  }

  function buildOrderListItemFromContext(card, row, mediaElement, imageUrl, rect) {
    const rowText = normalizeText(row.innerText || row.textContent || '').trim();
    const lines = rowText.split('\n').map((line) => line.trim()).filter(Boolean);
    const priceLine = lines.find((line) => parsePriceQuantityLine(line));
    const priceQuantity = priceLine ? parsePriceQuantityLine(priceLine) : null;
    const title = cleanTitle(
      readFirstText(row, [
        'a[href*="/item/"]',
        'a[href*="itemId="]',
        'a[href*="productId="]',
        '[title]',
      ]) || titleFromNearbyText(rowText) || mediaElement.getAttribute('alt') || mediaElement.getAttribute('title') || ''
    );
    if (!title || !isStrongProductTitle(title)) return null;

    const quantity = priceQuantity ? priceQuantity.quantity : extractQuantity(rowText);
    const money = priceQuantity ? { amount: priceQuantity.unitPrice, currency: priceQuantity.currency || 'CLP' } : parseBestMoney(rowText);
    const productUrl = findNearbyProductUrl(mediaElement) || findLocalProductUrlInRow(row);
    const itemId = extractItemId(productUrl) || extractItemId(rowText);
    const variant = extractVariant(rowText, title);
    const description = variant ? `${title} (${variant})` : title;
    const unitPrice = money ? money.amount : 0;
    return {
      sku: itemId ? `AE-${lastDigits(itemId, 8)}` : `AE-${String(Math.abs(hashText(description))).slice(0, 8)}`,
      lineTitle: title,
      description,
      variant,
      quantity: quantity || 1,
      unitPrice,
      total: roundMoney(unitPrice * (quantity || 1)),
      productUrl,
      itemId,
      imageUrl,
      _y: rect.top + window.scrollY,
      _x: rect.left + window.scrollX,
    };
  }

  function findOrderListItemRow(card, mediaElement) {
    let current = mediaElement;
    for (let depth = 0; depth < 8 && current && current !== card && current !== document.body; depth += 1) {
      const text = normalizeText(current.innerText || current.textContent || '').trim();
      if (text && text.length <= 1000 && !isPageChromeContainer(text) && !isRecommendationText(text)) {
        const hasMoney = extractMoneyTokens(text).length > 0 || /[x×]\s*\d/i.test(text);
        const hasTitle = titleFromNearbyText(text) || /\b(bike|bicycle|bicicleta|wake|shimano|sram|rockbros|pegatinas|palanca|freno)\b/i.test(text);
        if (hasMoney && hasTitle) return current;
      }
      current = current.parentElement;
    }
    return card;
  }

  function buildOrderListSummaryItem(card, orderNumber, totalMoney) {
    const text = normalizeText(card.innerText || card.textContent || '').trim();
    const title = titleFromNearbyText(text) || `AliExpress order ${orderNumber}`;
    const total = totalMoney ? totalMoney.amount : 0;
    return {
      sku: `AE-${lastDigits(orderNumber, 8)}`,
      lineTitle: title,
      description: title,
      variant: '',
      quantity: 1,
      unitPrice: total,
      total,
      productUrl: findOrderListDetailUrl(card, orderNumber) || location.href,
      itemId: '',
      imageUrl: imageSrc(card) || '',
    };
  }

  function isDateInRange(date, fromDate, toDate, dateFilterActive = Boolean(fromDate || toDate)) {
    if (!date) return !dateFilterActive;
    if (fromDate && date < fromDate) return false;
    if (toDate && date > toDate) return false;
    return true;
  }

  function buildOrderScope(fullText) {
    const boundaryY = findRecommendationBoundaryY();
    return {
      boundaryY,
      text: truncateAtRecommendationMarker(fullText),
    };
  }

  function truncateAtRecommendationMarker(text) {
    const markers = [
      /\n\s*more\s+to\s+love\s*\n/i,
      /\n\s*you\s+may\s+also\s+like\s*\n/i,
      /\n\s*recommended\s+for\s+you\s*\n/i,
      /\n\s*similar\s+items\s*\n/i,
      /\n\s*tambi[eé]n\s+te\s+puede\s+gustar\s*\n/i,
      /\n\s*m[aá]s\s+para\s+(?:amar|ti)\s*\n/i,
      /\n\s*productos\s+relacionados\s*\n/i,
      /\n\s*recomendad[oa]s?\s*\n/i,
    ];

    const matches = markers
      .map((pattern) => {
        const match = text.match(pattern);
        return match ? match.index : -1;
      })
      .filter((index) => index > 0);

    if (matches.length === 0) return text;
    return text.slice(0, Math.min(...matches));
  }

  function findRecommendationBoundaryY() {
    const markerPattern = /^(more\s+to\s+love|you\s+may\s+also\s+like|recommended\s+for\s+you|similar\s+items|tambi[eé]n\s+te\s+puede\s+gustar|m[aá]s\s+para\s+(?:amar|ti)|productos\s+relacionados|recomendad[oa]s?)(?:\b|\s|:|-)/i;
    const selectors = 'h1,h2,h3,h4,[role="heading"],section,div,span';
    let boundaryY = Number.POSITIVE_INFINITY;

    Array.from(document.querySelectorAll(selectors)).forEach((element) => {
      const label = normalizeText(element.innerText || element.textContent || '').replace(/\s+/g, ' ').trim();
      if (!label || !markerPattern.test(label.slice(0, 160))) return;
      const rect = element.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return;
      boundaryY = Math.min(boundaryY, rect.top + window.scrollY);
    });

    return boundaryY;
  }

  function normalizeText(value) {
    return String(value || '')
      .replace(/\r/g, '\n')
      .replace(/[\t\u00a0]+/g, ' ')
      .replace(/\n{3,}/g, '\n\n');
  }

  function extractOrderNumber(lines) {
    const patterns = [
      /(?:order\s*(?:id|number|no\.?|#)|pedido\s*(?:n[°o.]?|numero|number)?|numero\s+de\s+pedido|n[°o.]\s*de\s*pedido)\s*[:#]?\s*(\d{6,})/i,
      /\b(?:pedido|order)\b[^\n\d]{0,30}(\d{10,})/i,
    ];

    for (const line of lines) {
      for (const pattern of patterns) {
        const match = line.match(pattern);
        if (match) return match[1];
      }
    }

    for (let index = 0; index < lines.length - 1; index += 1) {
      if (/^(order\s*(id|number|no\.?|#)?|pedido\s*(n[°o.]?|numero)?|numero\s+de\s+pedido)$/i.test(lines[index])) {
        const nextMatch = lines[index + 1].match(/\b(\d{8,})\b/);
        if (nextMatch) return nextMatch[1];
      }
    }

    return '';
  }

  function extractOrderNumberFromUrl() {
    const url = new URL(location.href);
    const keys = ['orderId', 'orderIdList', 'orderNo', 'orderNoList', 'orderNumber'];

    for (const key of keys) {
      const value = url.searchParams.get(key);
      if (value) {
        const match = value.match(/\d{6,}/);
        if (match) return match[0];
      }
    }

    const pathMatch = location.pathname.match(/\b(\d{10,})\b/);
    return pathMatch ? pathMatch[1] : '';
  }

  function extractDate(lines) {
    const labelPattern = /(?:order\s*(?:date|time|placed)|placed\s+on|paid\s+on|purchase\s+date|date\s+purchased|fecha\s*(?:del\s*)?(?:pedido|compra)|comprado\s+el|pedido\s*(?:realizado|efectuado)(?:\s+el)?)\s*[:\-]?\s*(.+)/i;

    for (const line of lines.slice(0, 80)) {
      if (isDeliveryDateLine(line)) continue;
      const labelMatch = line.match(labelPattern);
      if (labelMatch) {
        const parsed = parseDateString(labelMatch[1] || labelMatch[0]);
        if (parsed) return parsed;
      }
    }

    for (let index = 0; index < Math.min(lines.length, 120); index += 1) {
      const line = lines[index];
      if (isNearDeliveryDateLine(lines, index)) continue;
      const parsed = parseDateString(line);
      if (parsed) return parsed;
    }

    return '';
  }

  function isDeliveryDateLine(line) {
    return /(estimated\s+delivery|delivery\s+date|entrega\s+estimada|fecha\s+de\s+entrega|env[ií]o\s+estimado)/i.test(line);
  }

  function isNearDeliveryDateLine(lines, index) {
    return isDeliveryDateLine(lines[index] || '')
      || isDeliveryDateLine(lines[index - 1] || '')
      || isDeliveryDateLine(lines[index + 1] || '');
  }

  function parseDateString(value) {
    const text = String(value || '').trim();

    let match = text.match(/\b(20\d{2})[\/-](\d{1,2})[\/-](\d{1,2})\b/);
    if (match) return toIsoDate(Number(match[1]), Number(match[2]), Number(match[3]));

    match = text.match(/\b(\d{1,2})[\/-](\d{1,2})[\/-](20\d{2}|\d{2})\b/);
    if (match) {
      const year = normalizeYear(Number(match[3]));
      const first = Number(match[1]);
      const second = Number(match[2]);
      if (first <= 12 && second > 12) return toIsoDate(year, first, second);
      return toIsoDate(year, second, first);
    }

    match = text.match(/\b([\p{L}.]+)\s+(\d{1,2}),?\s+(20\d{2})\b/u);
    if (match) return toIsoDate(Number(match[3]), monthNumber(match[1]), Number(match[2]));

    match = text.match(/\b(\d{1,2})\s+(?:de\s+)?([\p{L}.]+),?\s+(?:de\s+)?(20\d{2})\b/iu);
    if (match) return toIsoDate(Number(match[3]), monthNumber(match[2]), Number(match[1]));

    return '';
  }

  function normalizeYear(year) {
    return year < 100 ? 2000 + year : year;
  }

  function toIsoDate(year, month, day) {
    if (!year || !month || !day || month < 1 || month > 12 || day < 1 || day > 31) return '';
    return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  }

  function monthNumber(value) {
    const key = String(value || '').toLowerCase().replace('.', '').slice(0, 3);
    const months = {
      jan: 1,
      ene: 1,
      feb: 2,
      mar: 3,
      apr: 4,
      abr: 4,
      may: 5,
      jun: 6,
      jul: 7,
      aug: 8,
      ago: 8,
      sep: 9,
      oct: 10,
      nov: 11,
      dec: 12,
      dic: 12,
    };
    return months[key] || 0;
  }

  function extractTotals(lines) {
    const result = {
      currency: '',
      subtotal: null,
      shipping: null,
      tax: null,
      discount: null,
      total: null,
    };

    // [v0.3.51] Authoritative source: the expanded totals card captured during preload.
    // If that card balances (subtotal +/- shipping/tax/discount = total within tolerance),
    // trust it and skip the residual-to-tax fallback so promo "$800 coupon" text in the
    // page body cannot leak in as a fake discount or tax.
    const cardText = typeof globalThis.__AE_TOTALS_CARD_TEXT__ === 'string'
      ? globalThis.__AE_TOTALS_CARD_TEXT__
      : '';
    if (cardText) {
      const cardTotals = extractTotalsFromTextBlob(cardText);
      mergeTotalsSource(result, cardTotals);
      if (cardTotalsBalance(cardTotals)) {
        // Authoritative: do not let later sources or residual fallbacks invent values.
        return finalizeAuthoritativeTotals(result);
      }
    }

    mergeTotalsSource(result, extractTotalsFromTextBlob(lines.join('\n')));
    mergeTotalsSource(result, extractTotalsFromDom());

    const totalsTable = extractTotalsTable(lines);
    mergeTotalsSource(result, totalsTable);

    const fields = totalsLabelSpecs({ loose: true });

    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      for (const field of fields) {
        if (field.key === 'shipping') continue;
        if (!field.pattern.test(line)) continue;
        if (result[field.key] !== null) continue;
        const money = parseBestMoney(line) || parseBestMoney([line, ...lines.slice(index + 1, index + 4)].join(' '));
        if (!money) continue;
        recordTotalsField(result, field.key, money);
        result.currency = result.currency || money.currency;
      }
    }

    if (!result.total) {
      const tail = lines.slice(Math.max(0, lines.length - 80));
      const candidates = tail.map(parseBestMoney).filter(Boolean);
      candidates.sort((a, b) => b.amount - a.amount);
      if (candidates[0]) {
        result.total = candidates[0].amount;
        result.currency = result.currency || candidates[0].currency;
      }
    }

    if (result.subtotal && result.total) {
      const residual = roundMoney(result.total - result.subtotal - (result.shipping || 0) - (result.tax || 0) + Math.abs(result.discount || 0));
      if (residual > 0.01 && !result.tax && result.shipping !== null) {
        result.tax = residual;
      } else if (residual > 0.01 && !result.shipping && result.tax !== null) {
        result.shipping = residual;
      } else if (residual > 0.01 && !result.shipping && !result.tax) {
        result.tax = residual;
      }
    }

    // [v0.3.51] Final authoritative gate: even if the card text wasn't captured, if the
    // detail page's own totals balance arithmetically (subtotal + shipping + tax - discount = total),
    // mark the result authoritative so the popup merge will not overwrite null components with
    // noisy list-page values (which read item unit price as shipping).
    if (!result.__authoritative && result.subtotal && result.total) {
      const subtotalAmt = typeof result.subtotal === 'object' ? Math.abs(result.subtotal.amount || 0) : Math.abs(result.subtotal);
      const totalAmt = typeof result.total === 'object' ? Math.abs(result.total.amount || 0) : Math.abs(result.total);
      const shippingAmt = result.shipping ? (typeof result.shipping === 'object' ? Math.abs(result.shipping.amount || 0) : Math.abs(result.shipping)) : 0;
      const taxAmt = result.tax ? (typeof result.tax === 'object' ? Math.abs(result.tax.amount || 0) : Math.abs(result.tax)) : 0;
      const discountAmt = result.discount ? (typeof result.discount === 'object' ? Math.abs(result.discount.amount || 0) : Math.abs(result.discount)) : 0;
      const calc = roundMoney(subtotalAmt + shippingAmt + taxAmt - discountAmt);
      const tolerance = 2;
      if (Math.abs(roundMoney(totalAmt - calc)) <= tolerance) {
        result.__authoritative = true;
      }
    }

    return result;
  }

  function mergeTotalsSource(result, source) {
    Object.entries(source || {}).forEach(([key, money]) => {
      if (!money || result[key] !== null) return;
      recordTotalsField(result, key, money);
      result.currency = result.currency || money.currency;
    });
  }

  // A totals card is authoritative only when it closes within CLP rounding.
  function cardTotalsBalance(totals) {
    if (!totals || !totals.subtotal || !totals.total) return false;
    const subtotal = Math.abs(totals.subtotal.amount || 0);
    const total = Math.abs(totals.total.amount || 0);
    const shipping = Math.abs(totals.shipping?.amount || 0);
    const tax = Math.abs(totals.tax?.amount || 0);
    const discount = Math.abs(totals.discount?.amount || 0);
    const calc = roundMoney(subtotal + shipping + tax - discount);
    const tolerance = 2;
    return Math.abs(roundMoney(total - calc)) <= tolerance;
  }

  function finalizeAuthoritativeTotals(result) {
    return {
      currency: result.currency || '',
      subtotal: result.subtotal,
      shipping: result.shipping,
      tax: result.tax,
      discount: result.discount,
      total: result.total,
      __authoritative: true,
    };
  }

  function extractTotalsFromTextBlob(text) {
    const normalized = normalizeText(text || '').replace(/\r/g, '\n');
    const subtotalMatches = Array.from(normalized.matchAll(/(?:^|\n|\s)(subtotal|items\s*total|productos)(?:\s|:|：|$)/gi));
    if (!subtotalMatches.length) return {};

    const lastSubtotal = subtotalMatches[subtotalMatches.length - 1];
    const segmentStart = Math.max(0, lastSubtotal.index - 320);
    const segment = normalized.slice(segmentStart, lastSubtotal.index + 1600);
    return extractTotalsFromSegment(segment);
  }

  function extractTotalsFromSegment(segment) {
    const labelDefs = totalsTextLabelDefs();
    const matches = [];
    labelDefs.forEach((definition) => {
      const pattern = new RegExp(definition.pattern.source, 'gi');
      let match = pattern.exec(segment);
      while (match) {
        matches.push({ key: definition.key, index: match.index, end: pattern.lastIndex });
        match = pattern.exec(segment);
      }
    });

    matches.sort((a, b) => a.index - b.index || b.end - a.end);
    const afterFirst = extractTotalsFromMatches(segment, matches, false);
    const beforeFirst = extractTotalsFromMatches(segment, matches, true);
    return scoreTotalsCandidate(beforeFirst) > scoreTotalsCandidate(afterFirst)
      ? beforeFirst
      : afterFirst;
  }

  function extractTotalsFromMatches(segment, matches, preferBefore) {
    const result = {};
    for (let index = 0; index < matches.length; index += 1) {
      const current = matches[index];
      if (current.key !== 'discount' && result[current.key]) continue;
      const previous = [...matches].reverse().find((candidate) => candidate.end <= current.index && candidate.key !== current.key);
      const next = matches.find((candidate) => candidate.index >= current.end && candidate.key !== current.key);
      const afterEnd = next ? next.index : Math.min(segment.length, current.end + 180);
      const beforeStart = previous ? previous.end : Math.max(0, current.index - 80);
      const afterText = segment.slice(current.end, afterEnd).slice(0, 180);
      const beforeText = segment.slice(beforeStart, current.index).slice(-120);

      // [v0.3.51] "Free shipping" / "Envío gratis" must parse as shipping = 0 so the card
      // can balance and become authoritative; otherwise we fall back to noisy list values.
      if (current.key === 'shipping' && !result.shipping) {
        const freePattern = /\b(?:free\s*shipping|env[ií]o\s*(?:gratis|gratuito)|shipping\s*free|gratis)\b/i;
        if (freePattern.test(afterText) || freePattern.test(beforeText)) {
          result.shipping = { amount: 0, currency: '', raw: 'free' };
          continue;
        }
      }

      const afterMoney = parseFirstMoney(afterText) || parseBestMoney(afterText);
      const beforeMoney = nearestMoneyBeforeLabel(beforeText);
      const money = preferBefore
        ? (beforeMoney || afterMoney)
        : (afterMoney || beforeMoney);
      if (!money) continue;

      if (current.key === 'discount') {
        result.discount = {
          ...money,
          amount: roundMoney(Math.abs(result.discount?.amount || 0) + Math.abs(money.amount)),
        };
      } else {
        result[current.key] = money;
      }
    }
    return result;
  }

  function scoreTotalsCandidate(candidate) {
    const values = Object.fromEntries(
      Object.entries(candidate || {}).map(([key, money]) => [key, Math.abs(money?.amount || 0)]),
    );
    const fieldCount = ['subtotal', 'shipping', 'discount', 'tax', 'total']
      .reduce((count, key) => count + (values[key] !== undefined ? 1 : 0), 0);
    let score = fieldCount * 100;

    if (values.subtotal && values.total) {
      const calculatedTotal = roundMoney(values.subtotal + (values.shipping || 0) + (values.tax || 0) - (values.discount || 0));
      const residual = Math.abs(roundMoney(values.total - calculatedTotal));
      if (residual <= 1.01) score += 1000;
      else if (residual <= 10.01) score += 600;
      else if (residual <= 100.01) score += 150;
      else score -= Math.min(800, residual / 10);
    }

    if (values.shipping && values.discount && Math.abs(values.shipping - values.discount) <= 0.01) {
      score -= 250;
    }
    if (values.subtotal && values.shipping && values.shipping > values.subtotal * 0.35) {
      score -= 250;
    }
    return score;
  }

  function extractTotalsFromDom() {
    const labelSpecs = totalsLabelSpecs();
    const result = {};
    const elements = Array.from(document.querySelectorAll('span,div,p,li,dt,dd,td'));

    elements.forEach((element) => {
      if (!isVisibleElement(element)) return;
      const text = normalizeText(element.innerText || element.textContent || '').replace(/\s+/g, ' ').trim();
      if (!text || text.length > 120) return;
      const labelSpec = findTotalsLabelSpec(text, labelSpecs);
      if (!labelSpec) return;
      const money = findNearbyTotalsMoney(element, labelSpecs);
      if (!money) return;

      if (labelSpec.key === 'discount') {
        result.discount = {
          ...money,
          amount: roundMoney(Math.abs(result.discount?.amount || 0) + Math.abs(money.amount)),
        };
      } else if (!result[labelSpec.key]) {
        result[labelSpec.key] = money;
      }
    });

    return result;
  }

  function findNearbyTotalsMoney(element, labelSpecs) {
    const sameElementMoney = parseFirstMoney(element.innerText || element.textContent || '');
    if (sameElementMoney) return sameElementMoney;

    const siblings = Array.from(element.parentElement ? element.parentElement.children : []);
    const siblingIndex = siblings.indexOf(element);
    if (siblingIndex >= 0) {
      const indexes = [];
      for (let offset = 1; offset <= 4; offset += 1) {
        indexes.push(siblingIndex + offset, siblingIndex - offset);
      }
      for (const index of indexes) {
        if (index < 0 || index >= siblings.length) continue;
        const siblingText = normalizeText(siblings[index].innerText || siblings[index].textContent || '').replace(/\s+/g, ' ').trim();
        if (!siblingText) continue;
        if (findTotalsLabelSpec(siblingText, labelSpecs)) continue;
        const money = parseFirstMoney(siblingText);
        if (money) return money;
      }
    }

    let next = element.nextElementSibling;
    for (let hops = 0; next && hops < 4; hops += 1, next = next.nextElementSibling) {
      const text = normalizeText(next.innerText || next.textContent || '').replace(/\s+/g, ' ').trim();
      if (!text) continue;
      if (findTotalsLabelSpec(text, labelSpecs)) break;
      const money = parseFirstMoney(text);
      if (money) return money;
    }

    return null;
  }

  function isVisibleElement(element) {
    if (!element || !element.getBoundingClientRect) return false;
    const rect = element.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return false;
    const style = window.getComputedStyle ? window.getComputedStyle(element) : null;
    return !style || (style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0.01);
  }

  function recordTotalsField(result, key, money) {
    if (!money || !Number.isFinite(money.amount)) return;
    if (key === 'discount') {
      result.discount = roundMoney((result.discount || 0) + Math.abs(money.amount));
      return;
    }
    result[key] = Math.abs(money.amount);
  }

  function extractTotalsTable(lines) {
    const labelSpecs = totalsLabelSpecs();

    const startIndex = lines.findIndex((line) => /^(subtotal|items\s*total|productos)$/i.test(normalizeTotalsLabel(line)));
    if (startIndex < 0) return {};

    const tail = lines.slice(startIndex, Math.min(lines.length, startIndex + 40));
    const result = {};
    for (let index = 0; index < tail.length; index += 1) {
      const labelSpec = findTotalsLabelSpec(tail[index], labelSpecs);
      if (!labelSpec) continue;
      const money = findTotalsMoneyForLabel(tail, index, labelSpecs);
      if (!money) continue;

      const label = labelSpec.key;
      if (label === 'discount') {
        result.discount = {
          ...money,
          amount: roundMoney(Math.abs(result.discount?.amount || 0) + Math.abs(money.amount)),
        };
      } else if (!result[label]) {
        result[label] = money;
      }
    }
    return result;
  }

  function totalsLabelSpecs({ loose = false } = {}) {
    const start = loose ? '' : '^';
    const end = loose ? '' : '$';
    return [
      { key: 'subtotal', pattern: new RegExp(`${start}(subtotal|items\\s*total|productos)${end}`, 'i') },
      { key: 'shipping', pattern: new RegExp(`${start}(shipping(?:\\s*(?:fee|cost|total))?|delivery\\s*(?:fee|cost|total)|env.?o(?:\\s*(?:fee|cost|total|costo))?|entrega|flete)${end}`, 'i') },
      { key: 'tax', pattern: new RegExp(`${start}(tax|iva|impuesto)${end}`, 'i') },
      { key: 'discount', pattern: new RegExp(`${start}(discount|descuento|coupon|cupon|coins?|monedas?|ali\\s*express\\s*coupons?)${end}`, 'i') },
      { key: 'total', pattern: new RegExp(`${start}(order\\s*total|grand\\s*total|amount\\s*paid|payment\\s*total|total\\s*paid|total\\s*del\\s*pedido|total)${end}`, 'i') },
    ];
  }

  function totalsTextLabelDefs() {
    return [
      { key: 'subtotal', pattern: /\b(?:subtotal|items\s*total|productos)\b/i },
      { key: 'shipping', pattern: /\b(?:shipping(?:\s*(?:fee|cost|total))?|delivery\s*(?:fee|cost|total)|env.?o(?:\s*(?:fee|cost|total|costo))?|entrega|flete)\b/i },
      { key: 'tax', pattern: /\b(?:tax|iva|impuesto)\b/i },
      { key: 'discount', pattern: /\b(?:discount|descuento|coupon|cupon|coins?|monedas?|ali\s*express\s*coupons?)\b/i },
      { key: 'total', pattern: /\b(?:order\s*total|grand\s*total|amount\s*paid|payment\s*total|total\s*paid|total\s*del\s*pedido|total)\b/i },
    ];
  }

  function findTotalsLabelSpec(line, labelSpecs) {
    const label = normalizeTotalsLabel(line);
    return labelSpecs.find((spec) => spec.pattern.test(label)) || null;
  }

  function findTotalsMoneyForLabel(lines, labelIndex, labelSpecs) {
    const sameLineMoney = parseFirstMoney(lines[labelIndex]);
    if (sameLineMoney) return sameLineMoney;

    for (let index = labelIndex + 1; index < Math.min(lines.length, labelIndex + 5); index += 1) {
      if (findTotalsLabelSpec(lines[index], labelSpecs)) break;
      const money = parseFirstMoney(lines[index]);
      if (money) return money;
    }
    return null;
  }

  function normalizeTotalsLabel(line) {
    return String(line || '')
      .replace(/-?\s*(?:US\s*\$|USD|CLP\s*\$?|EUR|GBP|€|£|\$)\s*-?[\d.,]+|-?[\d.,]+\s*(?:USD|CLP|EUR|GBP)/gi, ' ')
      .replace(/[?:：]/g, ' ')
      .replace(/[ⓘ©®™]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function extractItems(defaultCurrency, orderScope, mediaItems = collectOrderMedia(orderScope)) {
    const domItems = extractItemsFromDom(defaultCurrency, orderScope, mediaItems);
    if (domItems.length > 0) return domItems;

    const textItems = extractItemsFromScopedText(orderScope.text, defaultCurrency, mediaItems);
    if (textItems.length > 0) return textItems;

    const anchors = Array.from(document.querySelectorAll('a[href]'))
      .filter((anchor) => isCandidateProductAnchor(anchor, orderScope));
    const usedContainers = new WeakSet();
    const seenRows = new Set();
    const itemIdCounts = new Map();
    const items = [];

    anchors.forEach((anchor) => {
      const productUrl = anchor.href;
      const itemId = extractItemId(productUrl);
      const title = cleanTitle(anchor.getAttribute('title') || anchor.innerText || imageAlt(anchor));
      if (!title || title.length < 6 || /aliexpress|view\s+detail|details|feedback/i.test(title)) return;

      const container = findProductContainer(anchor, title, orderScope);
      if (container && usedContainers.has(container)) return;
      const containerText = normalizeText(container ? container.innerText : anchor.innerText || title);
      if (isRecommendationText(containerText)) return;

      const quantity = extractQuantity(containerText) || 1;
      const monies = extractMoneyTokens(containerText);
      const priceInfo = resolveItemPrices(monies, quantity);
      if (!priceInfo.total && !priceInfo.unitPrice) return;

      const rowKey = buildProductRowKey(container || anchor, title, quantity, priceInfo.total);
      if (seenRows.has(rowKey)) return;

      const repeatedItemCount = itemId ? (itemIdCounts.get(itemId) || 0) + 1 : 0;
      if (itemId) itemIdCounts.set(itemId, repeatedItemCount);
      const baseSku = itemId ? `AE-${lastDigits(itemId, 8)}` : `AE-${String(items.length + 1).padStart(3, '0')}`;
      const sku = itemId && repeatedItemCount > 1 ? `${baseSku}-${String(repeatedItemCount).padStart(2, '0')}` : baseSku;
      const variant = extractVariant(containerText, title);
      const description = variant ? `${title} (${variant})` : title;

      if (container) usedContainers.add(container);
      seenRows.add(rowKey);
      items.push({
        sku,
        lineTitle: title,
        description,
        variant,
        quantity,
        unitPrice: priceInfo.unitPrice || priceInfo.total || 0,
        total: priceInfo.total || roundMoney((priceInfo.unitPrice || 0) * quantity),
        currency: priceInfo.currency || defaultCurrency || '',
        itemId: itemId || '',
        productUrl,
        imageUrl: imageSrc(container || anchor) || '',
      });
    });

    return dedupeExtractedItems(items).slice(0, 80);
  }

  function extractItemsFromDom(defaultCurrency, orderScope, mediaItems) {
    const imageAnchoredItems = extractItemsFromImageAnchoredRows(defaultCurrency, orderScope);
    if (imageAnchoredItems.length > 0) return imageAnchoredItems;

    const modernLayoutItems = extractItemsFromKnownModernLayout(defaultCurrency, orderScope);
    if (modernLayoutItems.length > 0) return modernLayoutItems;

    const visualItems = extractItemsFromVisualPriceRows(defaultCurrency, orderScope, mediaItems);
    if (visualItems.length > 0) return visualItems;

    const priceElements = Array.from(document.querySelectorAll('span,div,p,strong,b'))
      .filter((element) => {
        if (!isVisibleElement(element, orderScope)) return false;
        const text = normalizeText(element.innerText || element.textContent || '').trim();
        if (!text || text.length > 180) return false;
        return text.split('\n').some((line) => parsePriceQuantityLine(line.trim()));
      });

    const seenContainers = new WeakSet();
    const items = [];

    priceElements.forEach((priceElement) => {
      const container = findDomItemContainer(priceElement, orderScope);
      if (!container || seenContainers.has(container)) return;

      const item = buildDomItemFromContainer(container, defaultCurrency, mediaItems[items.length] || {});
      if (!item) return;

      seenContainers.add(container);
      items.push(item);
    });

    return dedupeExtractedItems(items).slice(0, 80);
  }

  function extractItemsFromImageAnchoredRows(defaultCurrency, orderScope) {
    const items = [];
    const usedRows = new WeakSet();

    collectCandidateImageElements(document).forEach((image) => {
      if (!isVisibleElement(image, orderScope)) return;

      const rect = image.getBoundingClientRect();
      const imageUrl = imageUrlFromElement(image);
      if (!imageUrl || rect.width < 40 || rect.height < 40) return;
      if (hasFloatingUiAncestor(image)) return;

      const row = findImageProductRow(image, orderScope);
      if (!row || usedRows.has(row)) return;

      const rowText = normalizeText(row.innerText || row.textContent || '').trim();
      if (!rowText || isRecommendationText(rowText) || isPageChromeContainer(rowText)) return;

      const lines = rowText.split('\n').map((line) => line.trim()).filter(Boolean);
      const priceLineIndex = lines.findIndex((line) => parsePriceQuantityLine(line));
      const priceQuantity = priceLineIndex >= 0 ? parsePriceQuantityLine(lines[priceLineIndex]) : null;
      const context = priceLineIndex >= 0 ? findLineItemContext(lines, priceLineIndex) : { title: '', variant: '' };
      const title = cleanTitle(
        readFirstText(row, [
          'div.item-title',
          '[class*="item-title"]',
          'a[href*="/item/"]',
          'a[href*="itemId="]',
          'a[href*="productId="]',
        ]) || context.title || image.getAttribute('alt') || image.getAttribute('title') || ''
      );
      if (!title || !isStrongProductTitle(title)) return;

      const quantity = priceQuantity ? priceQuantity.quantity : (extractQuantity(rowText) || 1);
      const moneySource = priceQuantity ? lines[priceLineIndex] : rowText;
      const priceInfo = priceQuantity
        ? {
            currency: priceQuantity.currency || defaultCurrency || 'CLP',
            unitPrice: priceQuantity.unitPrice,
            total: roundMoney(priceQuantity.unitPrice * priceQuantity.quantity),
          }
        : resolveItemPrices(extractMoneyTokens(moneySource), quantity);
      if (!priceInfo.unitPrice && !priceInfo.total) return;

      const productUrl = findLocalProductUrlInRow(row);
      const itemId = extractItemId(productUrl) || extractItemId(rowText);
      const rowImageUrl = pickPrimaryRowImage(row) || imageUrl;
      const variant = context.variant || extractVariant(rowText, title);
      const description = variant ? `${title} (${variant})` : title;
      const sku = itemId ? `AE-${lastDigits(itemId, 8)}` : `AE-${String(items.length + 1).padStart(3, '0')}`;

      usedRows.add(row);
      items.push({
        sku,
        lineTitle: title,
        description,
        variant,
        quantity,
        unitPrice: priceInfo.unitPrice || priceInfo.total || 0,
        total: priceInfo.total || roundMoney((priceInfo.unitPrice || 0) * quantity),
        currency: priceInfo.currency || defaultCurrency || 'CLP',
        itemId,
        productUrl,
        imageUrl: rowImageUrl,
      });
    });

    return dedupeExtractedItems(items).slice(0, 80);
  }

  function findImageProductRow(image, orderScope) {
    let current = image.parentElement;

    for (let depth = 0; depth < 8 && current && current !== document.body; depth += 1) {
      if (!isVisibleElement(current, orderScope)) {
        current = current.parentElement;
        continue;
      }

      const rect = current.getBoundingClientRect();
      if ((rect.width * rect.height) > (window.innerWidth * Math.max(window.innerHeight, 900) * 0.7)) {
        current = current.parentElement;
        continue;
      }

      const text = normalizeText(current.innerText || current.textContent || '').trim();
      if (!text || text.length > 2200 || isRecommendationText(text) || isPageChromeContainer(text)) {
        current = current.parentElement;
        continue;
      }

      const lines = text.split('\n').map((line) => line.trim()).filter(Boolean);
      const hasPrice = lines.some((line) => parsePriceQuantityLine(line)) || extractMoneyTokens(text).length > 0;
      if (!hasPrice) {
        current = current.parentElement;
        continue;
      }

      const localTitle = cleanTitle(readFirstText(current, [
        'div.item-title',
        '[class*="item-title"]',
        'a[href*="/item/"]',
        'a[href*="itemId="]',
        'a[href*="productId="]',
      ]));
      const hasTitle = Boolean(localTitle) || lines.some((line) => looksLikeProductTitle(line));
      if (hasTitle) return current;

      current = current.parentElement;
    }

    return null;
  }

  function extractItemsFromKnownModernLayout(defaultCurrency, orderScope) {
    const rowSelectors = [
      '.order-detail-item-content',
      '[class*="order-detail-item-content"]',
      '.order-item-content',
      '[class*="order-item-content"]',
    ];

    const rows = [];
    const seen = new WeakSet();
    rowSelectors.forEach((selector) => {
      Array.from(document.querySelectorAll(selector)).forEach((row) => {
        if (seen.has(row)) return;
        seen.add(row);
        rows.push(row);
      });
    });

    const items = [];
    rows.forEach((row) => {
      if (!isVisibleElement(row, orderScope)) return;

      const rowText = normalizeText(row.innerText || row.textContent || '').trim();
      if (!rowText || isRecommendationText(rowText) || isPageChromeContainer(rowText)) return;

      const title = cleanTitle(
        readFirstText(row, [
          'div.item-title',
          '[class*="item-title"]',
          'a[href*="/item/"]',
          'a[href*="itemId="]',
          'a[href*="productId="]',
        ])
      );
      if (!title || !isStrongProductTitle(title)) return;

      const priceBlock = readFirstText(row, [
        'div.item-price',
        '[class*="item-price"]',
        'div.price',
        '[class*="price"]',
      ]);
      const priceText = normalizeText(priceBlock || rowText).replace(/\n+/g, ' ').trim();
      const parsedPriceQuantity = parsePriceQuantityLine(priceText);
      const quantity = parsedPriceQuantity ? parsedPriceQuantity.quantity : (extractQuantity(rowText) || 1);
      const monies = extractMoneyTokens(priceText || rowText);
      const priceInfo = parsedPriceQuantity
        ? {
            currency: parsedPriceQuantity.currency || defaultCurrency || 'CLP',
            unitPrice: parsedPriceQuantity.unitPrice,
            total: roundMoney(parsedPriceQuantity.unitPrice * parsedPriceQuantity.quantity),
          }
        : resolveItemPrices(monies, quantity);

      if (!priceInfo.unitPrice && !priceInfo.total) return;

      const productUrl = findLocalProductUrlInRow(row);
      const itemId = extractItemId(productUrl) || extractItemId(rowText);
      const imageUrl = pickPrimaryRowImage(row);
      const variant = extractVariant(rowText, title);
      const description = variant ? `${title} (${variant})` : title;
      const sku = itemId ? `AE-${lastDigits(itemId, 8)}` : `AE-${String(items.length + 1).padStart(3, '0')}`;

      items.push({
        sku,
        lineTitle: title,
        description,
        variant,
        quantity,
        unitPrice: priceInfo.unitPrice || priceInfo.total || 0,
        total: priceInfo.total || roundMoney((priceInfo.unitPrice || 0) * quantity),
        currency: priceInfo.currency || defaultCurrency || 'CLP',
        itemId,
        productUrl,
        imageUrl,
      });
    });

    return dedupeExtractedItems(items).slice(0, 80);
  }

  function readFirstText(root, selectors) {
    for (const selector of selectors) {
      const node = root.querySelector(selector);
      const text = cleanTitle(node && (node.innerText || node.textContent || ''));
      if (text) return text;
    }
    return '';
  }

  function findLocalProductUrlInRow(row) {
    const link = row.querySelector('a[href*="/item/"],a[href*="itemId="],a[href*="productId="]');
    return link && link.href ? link.href : '';
  }

  function pickPrimaryRowImage(row) {
    const candidates = collectCandidateImageElements(row)
      .map((image) => {
        const rect = image.getBoundingClientRect();
        const imageUrl = imageUrlFromElement(image);
        if (!imageUrl || rect.width < 36 || rect.height < 36) return null;
        return {
          imageUrl,
          area: rect.width * rect.height,
          x: rect.left,
        };
      })
      .filter(Boolean)
      .sort((a, b) => b.area - a.area || a.x - b.x);

    return candidates[0] ? candidates[0].imageUrl : '';
  }

  function collectCentralOrderProductImages(orderScope) {
    const minX = Math.max(360, window.innerWidth * 0.30);
    const maxX = Math.max(minX + 80, window.innerWidth - 260);
    const candidates = collectCandidateImageElements(document)
      .map((image) => {
        if (!image || !image.getBoundingClientRect) return null;
        const rect = image.getBoundingClientRect();
        const y = rect.top + window.scrollY;
        const centerX = rect.left + (rect.width / 2);
        const imageUrl = imageUrlFromElement(image);

        if (!imageUrl || rect.width < 42 || rect.height < 52) return null;
        if (orderScope && y >= orderScope.boundaryY - 4) return null;
        if (centerX < minX || centerX > maxX) return null;
        if (hasFloatingUiAncestor(image) || hasRecommendationAncestor(image)) return null;
        if (!/alicdn|aliexpress|ae01|kf\//i.test(imageUrl)) return null;

        const contextText = mediaContextText(image);
        if (/qr|download|mobile\s+app|scan\s+or\s+click|need\s+help|support|avatar|cart|logo/i.test(`${imageUrl} ${contextText}`)) return null;

        const rowText = nearestReasonableAncestorText(image);
        const itemId = extractItemId(rowText) || extractItemId(findLocalProductUrlNearImage(image));
        const title = cleanTitle(titleFromNearbyText(rowText) || image.getAttribute('alt') || image.getAttribute('title') || '');
        return {
          y,
          x: rect.left + window.scrollX,
          area: rect.width * rect.height,
          sku: itemId ? `AE-${lastDigits(itemId, 8)}` : '',
          imageUrl,
          productUrl: findLocalProductUrlNearImage(image),
          itemId,
          title,
        };
      })
      .filter(Boolean)
      .sort((a, b) => a.y - b.y || b.area - a.area || a.x - b.x);

    const result = [];
    const seen = new Set();
    candidates.forEach((candidate) => {
      const rowKey = Math.round(candidate.y / 72);
      const key = candidate.itemId || `${rowKey}|${candidate.imageUrl.replace(/[?#].*$/, '')}`;
      if (seen.has(key)) return;
      seen.add(key);
      result.push({
        sku: candidate.sku,
        imageUrl: candidate.imageUrl,
        productUrl: candidate.productUrl,
        itemId: candidate.itemId,
        title: candidate.title,
      });
    });

    return result.slice(0, 40);
  }

  function collectVisibleOrderProductImageRects(orderScope) {
    const priceRowRects = collectVisiblePriceRowProductImageRects(orderScope);
    if (priceRowRects.length > 0) return priceRowRects;

    const minCenterX = Math.max(360, window.innerWidth * 0.28);
    const maxCenterX = Math.max(minCenterX + 120, window.innerWidth * 0.74);

    const candidates = collectCandidateImageElements(document)
      .map((image) => {
        if (!image || !image.getBoundingClientRect) return null;
        const rect = image.getBoundingClientRect();
        const centerX = rect.left + (rect.width / 2);
        if (rect.width < 52 || rect.height < 52 || rect.width > 180 || rect.height > 190) return null;
        if (rect.bottom <= 0 || rect.top >= window.innerHeight) return null;
        if (centerX < minCenterX || centerX > maxCenterX) return null;
        if (hasFloatingUiAncestor(image) || hasRecommendationAncestor(image)) return null;

        const pageY = rect.top + window.scrollY;
        if (orderScope && pageY >= orderScope.boundaryY - 4) return null;

        const row = findPurchasedOrderImageRow(image);
        if (!row) return null;
        const bestRowImage = bestImageInPurchasedOrderRow(row);
        if (!bestRowImage || bestRowImage.image !== image) return null;

        const imageUrl = bestRowImage.imageUrl;
        const productUrl = bestRowImage.productUrl;
        const rowText = normalizeText(row.innerText || row.textContent || '').trim();
        const context = `${rowText} ${mediaContextText(image)} ${image.alt || ''} ${image.title || ''}`;
        if (/qr|download|mobile\s+app|scan\s+or\s+click|need\s+help|support|avatar|cart|logo|coupon|feedback|review|more\s+to\s+love/i.test(context)) return null;

        const variantCodes = Array.from(new Set((rowText.match(/\b\d{8,14}\b/g) || [])
          .filter((code) => !/^100\d{10,18}$/.test(code))));
        if (variantCodes.length === 0) return null;
        const pad = 3;
        const area = rect.width * rect.height;
        const aspect = rect.width / Math.max(1, rect.height);
        return {
          left: Math.max(0, rect.left - pad),
          top: Math.max(0, rect.top - pad),
          width: Math.min(window.innerWidth - Math.max(0, rect.left - pad), rect.width + (pad * 2)),
          height: Math.min(window.innerHeight - Math.max(0, rect.top - pad), rect.height + (pad * 2)),
          pageY,
          pageX: rect.left + window.scrollX,
          variantCodes,
          itemId: extractItemId(rowText) || '',
          imageUrl,
          productUrl,
          rowText: cleanTitle(rowText).slice(0, 320),
          score: scorePurchasedRowImageCandidate(rect, aspect, area, productUrl, imageUrl),
        };
      })
      .filter(Boolean);

    return bestPurchasedRowImageRects(candidates)
      .sort((a, b) => a.pageY - b.pageY || a.pageX - b.pageX)
      .slice(0, 20);
  }

  function collectVisiblePriceRowProductImageRects(orderScope) {
    const rows = collectVisualPriceRows(orderScope)
      .filter((row) => row.rect.bottom > 0 && row.rect.top < window.innerHeight)
      .filter((row) => {
        const rowText = row.lines.join('\n');
        return !isRecommendationText(rowText) && !isPageChromeContainer(rowText);
      });

    if (rows.length === 0) return [];

    const images = collectCandidateImageElements(document)
      .map((image) => {
        if (!image || !image.getBoundingClientRect) return null;
        const rect = image.getBoundingClientRect();
        if (rect.width < 52 || rect.height < 52 || rect.width > 180 || rect.height > 190) return null;
        if (rect.bottom <= 0 || rect.top >= window.innerHeight) return null;
        if (hasFloatingUiAncestor(image) || hasRecommendationAncestor(image)) return null;
        const imageUrl = imageUrlFromElement(image);
        const productUrl = findLocalProductUrlNearImage(image);
        if (!isLikelyOrderProductPhoto(image, rect, imageUrl, productUrl)) return null;
        return {
          image,
          rect,
          imageUrl,
          productUrl,
          centerY: rect.top + (rect.height / 2),
          centerX: rect.left + (rect.width / 2),
          pageX: rect.left + window.scrollX,
          pageY: rect.top + window.scrollY,
          area: rect.width * rect.height,
        };
      })
      .filter(Boolean);

    const usedImages = new WeakSet();
    const candidates = rows.map((row) => {
      const rowCenterY = row.rect.top + (row.rect.height / 2);
      const rowText = row.lines.join('\n');
      const variantCodes = Array.from(new Set((rowText.match(/\b\d{8,14}\b/g) || [])
        .filter((code) => !/^100\d{10,18}$/.test(code))));
      if (variantCodes.length !== 1) return null;

      const bestImage = images
        .filter((candidate) => !usedImages.has(candidate.image))
        .map((candidate) => {
          const verticalDistance = Math.abs(candidate.centerY - rowCenterY);
          const leftOfPrice = candidate.centerX < row.rect.left + 80;
          const horizontalDistance = Math.abs(candidate.centerX - row.rect.left);
          if (verticalDistance > 150) return null;
          if (!leftOfPrice && horizontalDistance > 220) return null;

          const aspect = candidate.rect.width / Math.max(1, candidate.rect.height);
          const baseScore = scorePurchasedRowImageCandidate(candidate.rect, aspect, candidate.area, candidate.productUrl, candidate.imageUrl);
          return {
            ...candidate,
            distance: verticalDistance + (leftOfPrice ? 0 : 80) + Math.min(horizontalDistance, 360) / 12,
            score: baseScore - (verticalDistance * 260) - (leftOfPrice ? 0 : 12000),
          };
        })
        .filter(Boolean)
        .sort((a, b) => b.score - a.score || a.distance - b.distance)[0] || null;

      if (!bestImage) {
        const approximateRect = approximateProductImageRectForPriceRow(row);
        if (!approximateRect) return null;
        return productImageRectFromDomRect(approximateRect, {
          pageY: approximateRect.top + window.scrollY,
          pageX: approximateRect.left + window.scrollX,
          variantCodes,
          itemId: extractItemId(rowText) || '',
          imageUrl: '',
          productUrl: '',
          source: 'visual-row-approximation',
          rowText: cleanTitle(rowText).slice(0, 320),
        });
      }
      usedImages.add(bestImage.image);
      return productImageRectFromDomRect(bestImage.rect, {
        pageY: bestImage.pageY,
        pageX: bestImage.pageX,
        variantCodes,
        itemId: extractItemId(rowText) || '',
        imageUrl: bestImage.imageUrl,
        productUrl: bestImage.productUrl,
        source: 'visual-row-image',
        rowText: cleanTitle(rowText).slice(0, 320),
      });
    }).filter(Boolean);

    return candidates
      .sort((a, b) => a.pageY - b.pageY || a.pageX - b.pageX)
      .slice(0, 20);
  }

  function approximateProductImageRectForPriceRow(row) {
    const containerRect = findVisualProductRowContainerRect(row);
    if (!containerRect) return null;

    const size = Math.min(104, Math.max(74, containerRect.height - 18));
    const left = Math.max(0, containerRect.left + 8);
    const top = Math.max(0, containerRect.top + Math.max(4, (containerRect.height - size) / 2));
    if (left >= window.innerWidth || top >= window.innerHeight) return null;

    return {
      left,
      top,
      width: Math.min(size, window.innerWidth - left),
      height: Math.min(size, window.innerHeight - top),
    };
  }

  function findVisualProductRowContainerRect(row) {
    let current = row.element;
    for (let depth = 0; depth < 7 && current && current !== document.body; depth += 1) {
      if (!current.getBoundingClientRect) {
        current = current.parentElement;
        continue;
      }

      const rect = current.getBoundingClientRect();
      const text = normalizeText(current.innerText || current.textContent || '').trim();
      const reasonableSize = rect.width >= 360 && rect.width <= Math.max(1200, window.innerWidth * 0.88)
        && rect.height >= 58 && rect.height <= 260;
      if (reasonableSize && text.length <= 1600 && isPurchasedProductImageRowText(text)) return rect;
      current = current.parentElement;
    }

    return row.rect && row.rect.height >= 58 ? row.rect : null;
  }

  function productImageRectFromDomRect(rect, metadata) {
    const pad = 3;
    const left = Math.max(0, rect.left - pad);
    const top = Math.max(0, rect.top - pad);
    return {
      left,
      top,
      width: Math.min(window.innerWidth - left, rect.width + (pad * 2)),
      height: Math.min(window.innerHeight - top, rect.height + (pad * 2)),
      ...metadata,
    };
  }

  function isLikelyOrderProductPhoto(image, rect, imageUrl, productUrl) {
    if (!imageUrl) return false;
    if (isPlaceholderImageUrl(imageUrl)) return false;
    if (/sprite|logo|avatar|qr|barcode|icon|loading|transparent|placeholder|feedback|coupon|badge|choice|brand|certified|original|commitment|arrow|tag|label/i.test(imageUrl)) {
      return false;
    }

    const localContext = [
      image.alt,
      image.title,
      image.getAttribute('aria-label'),
      image.getAttribute('class'),
      image.getAttribute('id'),
      mediaContextText(image).slice(0, 280),
    ].filter(Boolean).join(' ');

    if (/qr|download|mobile\s+app|support|avatar|cart|logo|coupon|feedback|review|choice|certified\s+original|commitment|badge|icon/i.test(localContext)) {
      return false;
    }

    const area = rect.width * rect.height;
    const aspect = rect.width / Math.max(1, rect.height);
    const productSized = area >= 3600 && rect.width >= 58 && rect.height >= 58;
    const tallProductSized = area >= 3000 && rect.height >= 66 && aspect >= 0.34 && aspect <= 0.95;
    return Boolean(productUrl) || productSized || tallProductSized;
  }

  function scorePurchasedRowImageCandidate(rect, aspect, area, productUrl, imageUrl) {
    let score = area + (rect.height * 160) + (rect.width * 20);
    if (productUrl) score += 120000;
    if (/alicdn\.com\/(?:kf|imgextra|bao\/uploaded)/i.test(imageUrl || '')) score += 18000;
    if (rect.height >= 62) score += 8000;
    if (aspect >= 0.38 && aspect <= 0.86) score += 12000;
    if (aspect >= 0.92 && aspect <= 1.18 && area < 5200) score -= 18000;
    if (rect.width < 58 || rect.height < 58) score -= 12000;
    return score;
  }

  function bestPurchasedRowImageRects(candidates) {
    const bestByVariant = new Map();
    candidates.forEach((candidate) => {
      const key = candidate.variantCodes[0] || `row:${Math.round(candidate.pageY / 96)}`;
      const existing = bestByVariant.get(key);
      if (!existing || candidate.score > existing.score) bestByVariant.set(key, candidate);
    });
    return Array.from(bestByVariant.values()).map((candidate) => {
      const { score, ...publicCandidate } = candidate;
      return publicCandidate;
    });
  }

  function findPurchasedOrderImageRow(image) {
    let current = image;
    for (let depth = 0; depth < 9 && current && current !== document.body; depth += 1) {
      const rect = current.getBoundingClientRect ? current.getBoundingClientRect() : null;
      if (rect && (rect.height > 340 || rect.width > Math.max(960, window.innerWidth * 0.82))) {
        current = current.parentElement;
        continue;
      }

      const text = normalizeText(current.innerText || current.textContent || '').trim();
      if (text && text.length <= 1400 && isPurchasedProductImageRowText(text)) return current;
      current = current.parentElement;
    }
    return null;
  }

  function bestImageInPurchasedOrderRow(row) {
    return collectCandidateImageElements(row)
      .map((candidateImage) => {
        if (!candidateImage || !candidateImage.getBoundingClientRect) return null;
        const candidateRect = candidateImage.getBoundingClientRect();
        if (candidateRect.width < 52 || candidateRect.height < 52 || candidateRect.width > 180 || candidateRect.height > 190) return null;
        if (candidateRect.bottom <= 0 || candidateRect.top >= window.innerHeight) return null;
        const candidateImageUrl = imageUrlFromElement(candidateImage);
        const candidateProductUrl = findLocalProductUrlNearImage(candidateImage);
        if (!isLikelyOrderProductPhoto(candidateImage, candidateRect, candidateImageUrl, candidateProductUrl)) return null;
        const candidateArea = candidateRect.width * candidateRect.height;
        const candidateAspect = candidateRect.width / Math.max(1, candidateRect.height);
        return {
          image: candidateImage,
          imageUrl: candidateImageUrl,
          productUrl: candidateProductUrl,
          score: scorePurchasedRowImageCandidate(candidateRect, candidateAspect, candidateArea, candidateProductUrl, candidateImageUrl),
          pageX: candidateRect.left + window.scrollX,
        };
      })
      .filter(Boolean)
      .sort((a, b) => b.score - a.score || a.pageX - b.pageX)[0] || null;
  }

  function findPurchasedOrderImageRowText(image) {
    const row = findPurchasedOrderImageRow(image);
    return row ? normalizeText(row.innerText || row.textContent || '').trim() : '';
  }

  function isPurchasedOrderRowText(text) {
    const value = normalizeText(text || '');
    if (!value || isRecommendationText(value) || isPageChromeContainer(value)) return false;
    const codes = (value.match(/\b\d{8,14}\b/g) || []).filter((code) => !/^100\d{10,18}$/.test(code));
    if (codes.length === 0) return false;
    const hasLinePrice = /(?:CLP\s*)?\$\s*\d|\b\d+[.,]\d{3}\b/.test(value);
    const hasOrderLineSignal = /\bestimated\s+delivery\s+date\b|\bfast\s+delivery\b|\bx\s*\d+\b|\bdelivered\b|\bpaid\b/i.test(value);
    const hasProductText = /\b(rockbros|bike|bicycle|bicicleta|cycling|ciclismo|botella|water\s+bottle)\b/i.test(value);
    return hasLinePrice && hasOrderLineSignal && hasProductText;
  }

  function isPurchasedProductImageRowText(text) {
    const value = normalizeText(text || '');
    if (!value || isRecommendationText(value) || isPageChromeContainer(value)) return false;
    if (/fast\s+delivery\s*:\s*active|certified\s+original|aliexpress\s+commitment|return&refund\s+policy|order\s+complete|track\s+order|write\s+a\s+review|add\s+to\s+cart/i.test(value)) {
      return false;
    }

    const codes = (value.match(/\b\d{8,14}\b/g) || []).filter((code) => !/^100\d{10,18}$/.test(code));
    if (codes.length === 0) return false;

    const lines = value.split('\n').map((line) => line.trim()).filter(Boolean);
    const hasPriceQuantityLine = lines.some((line) => parsePriceQuantityLine(line))
      || /(?:CLP\s*)?\$?\s*\d[\d.,]*\s*[x×]\s*\d+/i.test(value);
    if (!hasPriceQuantityLine) return false;

    const hasProductTitle = lines.some((line) => isStrongProductTitle(line))
      || /\b(rockbros|bike|bicycle|bicicleta|cycling|ciclismo|botella|water\s+bottle)\b/i.test(value);
    return hasProductTitle;
  }

  function nearestReasonableAncestorText(element) {
    let current = element;
    for (let depth = 0; depth < 8 && current && current !== document.body; depth += 1) {
      const text = normalizeText(current.innerText || current.textContent || '').trim();
      if (text && text.length <= 1600 && !isPageChromeContainer(text) && !isRecommendationText(text)) return text;
      current = current.parentElement;
    }
    return '';
  }

  function titleFromNearbyText(text) {
    const lines = String(text || '').split('\n').map((line) => cleanTitle(line)).filter(Boolean);
    return lines.find((line) => isStrongProductTitle(line)) || '';
  }

  function findLocalProductUrlNearImage(image) {
    let current = image;
    for (let depth = 0; depth < 7 && current && current !== document.body; depth += 1) {
      const link = current.querySelector ? current.querySelector('a[href*="/item/"],a[href*="itemId="],a[href*="productId="]') : null;
      if (link && link.href) return link.href;
      current = current.parentElement;
    }
    return '';
  }

  function extractItemsFromVisualPriceRows(defaultCurrency, orderScope, mediaItems) {
    const priceRows = collectVisualPriceRows(orderScope);
    if (priceRows.length === 0) return [];

    const mediaByPosition = collectPositionedProductMedia(orderScope);
    const anchorsByPosition = collectPositionedProductAnchors(orderScope);
    const items = [];

    priceRows.forEach((row) => {
      const media = findClosestPositionedMedia(row, mediaByPosition) || mediaItems[items.length] || {};
      const anchor = findClosestPositionedAnchor(row, anchorsByPosition);
      const context = findLineItemContext(row.lines, row.priceLineIndex);
      const mediaTitle = cleanTitle(media.title || anchor.title || '');
      const title = cleanTitle(context.title || mediaTitle || 'AliExpress item');

      if (!isStrongProductTitle(title) && title !== 'AliExpress item' && !media.imageUrl && !anchor.productUrl) return;

      const productUrl = anchor.productUrl || media.productUrl || '';
      const itemId = extractItemId(productUrl) || media.itemId || '';
      const imageUrl = media.imageUrl || '';
      const description = context.variant && title !== 'AliExpress item'
        ? `${title} (${context.variant})`
        : title;
      const sku = itemId ? `AE-${lastDigits(itemId, 8)}` : `AE-${String(items.length + 1).padStart(3, '0')}`;

      items.push({
        sku,
        lineTitle: title,
        description,
        variant: context.variant || '',
        quantity: row.priceQuantity.quantity,
        unitPrice: row.priceQuantity.unitPrice,
        total: roundMoney(row.priceQuantity.unitPrice * row.priceQuantity.quantity),
        currency: row.priceQuantity.currency || defaultCurrency || 'CLP',
        itemId,
        productUrl,
        imageUrl,
        _visualRowY: Math.round(row.y),
      });
    });

    return dedupeVisualItems(items).slice(0, 80);
  }

  function collectVisualPriceRows(orderScope) {
    const rows = [];
    const seen = new Set();

    Array.from(document.querySelectorAll('span,div,p,strong,b'))
      .filter((element) => isVisibleElement(element, orderScope))
      .forEach((element) => {
        const text = normalizeText(element.innerText || element.textContent || '').trim();
        if (!text || text.length > 1400 || isPageChromeContainer(text)) return;

        const lines = text.split('\n').map((line) => line.trim()).filter(Boolean);
        const priceLineIndex = lines.findIndex((line) => parsePriceQuantityLine(line));
        if (priceLineIndex < 0) return;

        const priceQuantity = parsePriceQuantityLine(lines[priceLineIndex]);
        if (!priceQuantity) return;

        const rect = element.getBoundingClientRect();
        const y = rect.top + window.scrollY;
        const key = `${Math.round(y / 12)}|${priceQuantity.unitPrice}|${priceQuantity.quantity}`;
        if (seen.has(key)) return;
        seen.add(key);

        rows.push({
          element,
          rect,
          y,
          x: rect.left + window.scrollX,
          lines,
          priceLineIndex,
          priceQuantity,
        });
      });

    return rows.sort((a, b) => a.y - b.y || a.x - b.x);
  }

  function collectPositionedProductMedia(orderScope) {
    return collectCandidateImageElements(document)
      .map((image) => {
        if (!isVisibleElement(image, orderScope)) return null;
        const rect = image.getBoundingClientRect();
        const imageUrl = imageUrlFromElement(image);
        if (!imageUrl || rect.width < 35 || rect.height < 35) return null;
        if (!/alicdn|aliexpress|ae01|kf\//i.test(imageUrl)) return null;

        const productUrl = findNearbyProductUrl(image);
        if (isIgnoredMediaImage(image, rect, imageUrl, productUrl)) return null;

        return {
          y: rect.top + window.scrollY,
          x: rect.left + window.scrollX,
          height: rect.height,
          width: rect.width,
          imageUrl,
          productUrl,
          itemId: extractItemId(productUrl),
          title: cleanTitle(image.getAttribute('alt') || image.getAttribute('title') || ''),
        };
      })
      .filter(Boolean)
      .sort((a, b) => a.y - b.y || a.x - b.x);
  }

  function collectPositionedProductAnchors(orderScope) {
    return Array.from(document.querySelectorAll('a[href*="/item/"],a[href*="itemId="],a[href*="productId="]'))
      .map((anchor) => {
        if (!isVisibleElement(anchor, orderScope)) return null;
        const rect = anchor.getBoundingClientRect();
        const title = cleanTitle(anchor.getAttribute('title') || anchor.innerText || imageAlt(anchor) || '');
        if (!title && !anchor.href) return null;
        return {
          y: rect.top + window.scrollY,
          x: rect.left + window.scrollX,
          height: rect.height,
          width: rect.width,
          productUrl: anchor.href,
          title,
        };
      })
      .filter(Boolean)
      .sort((a, b) => a.y - b.y || a.x - b.x);
  }

  function findClosestPositionedMedia(row, mediaItems) {
    return mediaItems
      .map((media) => ({ media, distance: visualRowDistance(row, media) }))
      .filter((entry) => entry.distance < 260)
      .sort((a, b) => a.distance - b.distance)[0]?.media || null;
  }

  function findClosestPositionedAnchor(row, anchors) {
    return anchors
      .map((anchor) => ({ anchor, distance: visualRowDistance(row, anchor) }))
      .filter((entry) => entry.distance < 320)
      .sort((a, b) => a.distance - b.distance)[0]?.anchor || null;
  }

  function visualRowDistance(row, candidate) {
    const rowCenterY = row.y + (row.rect.height || 0) / 2;
    const candidateCenterY = candidate.y + (candidate.height || 0) / 2;
    const verticalDistance = Math.abs(rowCenterY - candidateCenterY);
    const horizontalPenalty = candidate.x <= row.x + 80 ? 0 : 80;
    return verticalDistance + horizontalPenalty;
  }

  function dedupeVisualItems(items) {
    const result = [];
    const seen = new Set();

    items.forEach((rawItem) => {
      const explicitVariantKey = explicitVariantIdentityKeyFromItem(rawItem) || 'default';
      const item = withSupplierVariantIdentity(rawItem);
      const imageKey = item.imageUrl ? normalizeImageUrl(item.imageUrl).replace(/[?#].*$/, '') : '';
      const titleKey = dedupeTextKey(item.description);
      const rowKey = item._visualRowY ? Math.round(item._visualRowY / 18) : result.length;
      const key = item.itemId
        ? `id:${item.itemId}:${explicitVariantKey}:${item.unitPrice}:${item.quantity}:${titleKey}:${imageKey || rowKey}`
        : `${titleKey}|${explicitVariantKey}|${item.unitPrice}|${item.quantity}|${imageKey || rowKey}`;
      if (seen.has(key)) return;
      seen.add(key);
      result.push(item);
    });

    return result;
  }

  function findDomItemContainer(priceElement, orderScope) {
    let current = priceElement;

    for (let depth = 0; depth < 9 && current && current !== document.body; depth += 1) {
      if (!isVisibleElement(current, orderScope)) {
        current = current.parentElement;
        continue;
      }

      const text = normalizeText(current.innerText || current.textContent || '');
      if (!text || text.length > 2600 || isRecommendationText(text)) {
        current = current.parentElement;
        continue;
      }

      const lines = text.split('\n').map((line) => line.trim()).filter(Boolean);
      const priceLineIndex = lines.findIndex((line) => parsePriceQuantityLine(line));
      if (priceLineIndex < 0) {
        current = current.parentElement;
        continue;
      }

      const context = findLineItemContext(lines, priceLineIndex);
      const mediaTitle = titleFromContainerMedia(current);
      const imageUrl = imageSrc(current);
      const productUrl = findNearbyProductUrl(current);
      const title = cleanTitle(context.title || mediaTitle);
      const hasItemEvidence = Boolean(productUrl || imageUrl || mediaTitle);

      if (!isPageChromeContainer(text) && (isStrongProductTitle(title) || hasItemEvidence)) {
        return current;
      }

      current = current.parentElement;
    }

    return null;
  }

  function buildDomItemFromContainer(container, defaultCurrency, fallbackMedia) {
    const text = normalizeText(container.innerText || container.textContent || '');
    const lines = text.split('\n').map((line) => line.trim()).filter(Boolean);
    const priceLineIndex = lines.findIndex((line) => parsePriceQuantityLine(line));
    if (priceLineIndex < 0) return null;

    const priceQuantity = parsePriceQuantityLine(lines[priceLineIndex]);
    if (!priceQuantity) return null;

    const context = findLineItemContext(lines, priceLineIndex);
    const mediaTitle = titleFromContainerMedia(container);
    const title = cleanTitle(context.title || mediaTitle);
    if (!isStrongProductTitle(title) && !mediaTitle) return null;

    const productUrl = findNearbyProductUrl(container) || fallbackMedia.productUrl || '';
    const itemId = extractItemId(productUrl) || fallbackMedia.itemId || '';
    const imageUrl = imageSrc(container) || fallbackMedia.imageUrl || '';
    const description = context.variant ? `${title} (${context.variant})` : title;
    const sku = itemId ? `AE-${lastDigits(itemId, 8)}` : `AE-${String(Math.abs(hashText(description)).toString()).slice(0, 6).padStart(6, '0')}`;

    return {
      sku,
      lineTitle: title,
      description,
      variant: context.variant || '',
      quantity: priceQuantity.quantity,
      unitPrice: priceQuantity.unitPrice,
      total: roundMoney(priceQuantity.unitPrice * priceQuantity.quantity),
      currency: priceQuantity.currency || defaultCurrency || 'CLP',
      itemId,
      productUrl,
      imageUrl,
    };
  }

  function titleFromContainerMedia(container) {
    const candidates = [];

    Array.from(container.querySelectorAll('a[title],a[href*="/item/"],a[href*="itemId="],img[alt],img[title]')).forEach((element) => {
      candidates.push(element.getAttribute('title'));
      candidates.push(element.getAttribute('alt'));
      if (element.matches && element.matches('a')) candidates.push(element.innerText || element.textContent || '');
    });

    return candidates
      .map(cleanTitle)
      .filter((candidate) => isMeaningfulItemContextLine(candidate) && isStrongProductTitle(candidate))
      .sort((a, b) => b.length - a.length)[0] || '';
  }

  function extractItemsFromScopedText(scopedText, defaultCurrency, mediaItems) {
    const lines = scopedText.split('\n').map((line) => line.trim()).filter(Boolean);
    const items = [];
    const seen = new Set();

    for (let index = 0; index < lines.length; index += 1) {
      const priceQuantity = parsePriceQuantityLine(lines[index]);
      if (!priceQuantity) continue;

      const context = findLineItemContext(lines, index);
      if (!context.title) continue;

      const rowKey = `${dedupeTextKey(context.title)}|${priceQuantity.unitPrice}|${priceQuantity.quantity}`;
      if (seen.has(rowKey)) continue;
      seen.add(rowKey);

      const description = context.variant ? `${context.title} (${context.variant})` : context.title;
      const media = mediaItems[items.length] || {};
      const itemId = media.itemId || '';
      const sku = itemId ? `AE-${lastDigits(itemId, 8)}` : `AE-${String(items.length + 1).padStart(3, '0')}`;

      items.push({
        sku,
        lineTitle: context.title,
        description,
        variant: context.variant || '',
        quantity: priceQuantity.quantity,
        unitPrice: priceQuantity.unitPrice,
        total: roundMoney(priceQuantity.unitPrice * priceQuantity.quantity),
        currency: 'CLP',
        itemId,
        productUrl: media.productUrl || '',
        imageUrl: media.imageUrl || '',
      });
    }

    return dedupeExtractedItems(items);
  }

  function collectOrderMedia(orderScope) {
    const candidates = collectCandidateImageElements(document)
      .map((image) => {
        const rect = image.getBoundingClientRect();
        const y = rect.top + window.scrollY;
        const imageUrl = normalizeImageUrl(
          image.currentSrc
          || image.src
          || image.getAttribute('data-src')
          || image.getAttribute('data-lazy-src')
          || '',
        );

        if (!imageUrl || rect.width < 35 || rect.height < 35) return null;
        if (y >= orderScope.boundaryY - 4) return null;
        if (hasRecommendationAncestor(image)) return null;
        if (!/alicdn|aliexpress|ae01|kf\//i.test(imageUrl)) return null;

        const productUrl = findNearbyProductUrl(image);
        if (isIgnoredMediaImage(image, rect, imageUrl, productUrl)) return null;
        return {
          y,
          x: rect.left + window.scrollX,
          width: rect.width,
          height: rect.height,
          area: rect.width * rect.height,
          score: mediaScore(image, rect, productUrl),
          imageUrl,
          productUrl,
          itemId: extractItemId(productUrl),
          title: cleanTitle(image.getAttribute('alt') || image.getAttribute('title') || ''),
        };
      })
      .filter(Boolean)
      .sort((a, b) => b.score - a.score || a.y - b.y || b.area - a.area);

    const bestByKey = new Map();
    candidates.forEach((candidate) => {
      const key = mediaIdentityKey(candidate);
      const existing = bestByKey.get(key);
      if (!existing || mediaCandidateQuality(candidate) > mediaCandidateQuality(existing)) {
        bestByKey.set(key, candidate);
      }
    });

    return Array.from(bestByKey.values())
      .sort((a, b) => a.y - b.y || b.score - a.score || b.area - a.area || a.x - b.x);
  }

  function normalizeImageUrl(url) {
    const value = String(url || '').trim();
    if (!value) return '';
    if (value.startsWith('//')) return `https:${value}`;
    return value;
  }

  function collectCandidateImageElements(root = document) {
    const scope = root && root.querySelectorAll ? root : document;
    const selectors = [
      'img',
      '[style*="background"]',
      '[data-src]',
      '[data-lazy-src]',
      '[data-original]',
      '[data-actualsrc]',
      '[data-image]',
      '[data-img]',
    ];
    const seen = new Set();
    const result = [];

    selectors.forEach((selector) => {
      Array.from(scope.querySelectorAll(selector)).forEach((element) => {
        if (!element || seen.has(element)) return;
        seen.add(element);
        result.push(element);
      });
    });

    Array.from(scope.querySelectorAll('a,div,span,p')).forEach((element) => {
      if (!element || seen.has(element) || !element.getBoundingClientRect) return;
      const rect = element.getBoundingClientRect();
      if (rect.width < 24 || rect.height < 24 || rect.width > 260 || rect.height > 260) return;
      const backgroundImage = window.getComputedStyle(element).backgroundImage;
      if (!cssImageUrls(backgroundImage).some((url) => /alicdn|aliexpress|ae01|kf\//i.test(url))) return;
      seen.add(element);
      result.push(element);
    });

    if (scope !== document && scope.matches && selectors.some((selector) => scope.matches(selector)) && !seen.has(scope)) {
      result.unshift(scope);
    }

    return result;
  }

  function cssImageUrls(value) {
    const urls = [];
    const pattern = /url\((['"]?)(.*?)\1\)/gi;
    let match;
    while ((match = pattern.exec(String(value || ''))) !== null) {
      if (match[2]) urls.push(match[2]);
    }
    return urls;
  }

  function imageUrlFromElement(image) {
    if (!image || !image.getAttribute) return '';

    const srcsetCandidates = String(image.getAttribute('srcset') || '')
      .split(',')
      .map((entry) => entry.trim().split(/\s+/)[0] || '')
      .filter(Boolean)
      .reverse();

    const candidates = [
      image.getAttribute('data-src'),
      image.getAttribute('data-lazy-src'),
      image.getAttribute('data-original'),
      image.getAttribute('data-actualsrc'),
      image.getAttribute('data-image'),
      image.getAttribute('data-img'),
      image.getAttribute('src'),
      ...srcsetCandidates,
      image.currentSrc,
      image.src,
      ...cssImageUrls(image.getAttribute('style')),
      ...cssImageUrls(image.style && image.style.backgroundImage),
      ...cssImageUrls(window.getComputedStyle(image).backgroundImage),
    ]
      .map(normalizeImageUrl)
      .filter(Boolean);

    return candidates.find((url) => !isPlaceholderImageUrl(url)) || candidates[0] || '';
  }

  function isPlaceholderImageUrl(url) {
    return /^data:image\/(?:gif|svg\+xml)/i.test(url)
      || /(?:transparent|placeholder|loading|spinner|blank|pixel|1x1|grey\.gif|empty)/i.test(url);
  }

  function isIgnoredMediaImage(image, rect, imageUrl, productUrl) {
    if (hasFloatingUiAncestor(image)) return true;
    if (looksLikeSupportOrChromeImage(image, imageUrl) && !productUrl) return true;
    if (isViewportCornerWidget(rect) && !productUrl) return true;
    if (!productUrl && !hasProductMediaContext(image) && !looksLikeCatalogImage(imageUrl, rect)) return true;
    return false;
  }

  function mediaScore(image, rect, productUrl) {
    let score = 0;
    if (productUrl) score += 100;
    if (hasProductMediaContext(image)) score += 60;
    if (looksLikeCatalogImage('', rect)) score += 20;
    if (Math.min(rect.width, rect.height) >= 72) score += 26;
    else if (Math.min(rect.width, rect.height) >= 56) score += 14;
    else if (Math.min(rect.width, rect.height) < 44) score -= 18;
    if ((rect.width * rect.height) >= 5500) score += 16;
    else if ((rect.width * rect.height) < 2200) score -= 14;
    if (rect.left > 120 && rect.left < window.innerWidth - 220) score += 10;
    if (rect.top > 120) score += 6;
    return score;
  }

  function mediaIdentityKey(candidate) {
    const imageKey = candidate.imageUrl ? normalizeImageUrl(candidate.imageUrl).replace(/[?#].*$/, '') : '';
    const rowKey = `row:${Math.round((candidate.y || 0) / 56)}`;
    if (candidate.itemId) return `item:${candidate.itemId}:${imageKey || rowKey}`;
    const productKey = normalizeProductUrl(candidate.productUrl);
    if (productKey) return `url:${productKey}:${imageKey || rowKey}`;
    return imageKey || rowKey;
  }

  function mediaCandidateQuality(candidate) {
    return (candidate.score * 100000) + Math.round(candidate.area || 0);
  }

  function hasFloatingUiAncestor(element) {
    let current = element;
    for (let depth = 0; depth < 8 && current && current !== document.body; depth += 1) {
      const style = window.getComputedStyle(current);
      if (style.position === 'fixed' || style.position === 'sticky') return true;
      current = current.parentElement;
    }
    return false;
  }

  function looksLikeSupportOrChromeImage(image, imageUrl) {
    const context = mediaContextText(image);
    const attrs = [
      image.alt,
      image.title,
      image.getAttribute('aria-label'),
      image.getAttribute('class'),
      image.getAttribute('id'),
      imageUrl,
      context,
    ].filter(Boolean).join(' ');

    return /\b(need\s+help|help|support|customer\s+service|service\s+commitment|fast\s+delivery|return\s*&?\s*refund|message\s+center|mobile\s+app|search\s+anywhere|download|qr|chat|cart|avatar|login|sign\s*in|coupon|feedback|store\s+badge|badge|icon|sprite|logo)\b/i.test(attrs);
  }

  function isViewportCornerWidget(rect) {
    const nearRight = rect.left > Math.max(0, window.innerWidth - 180);
    const nearBottom = rect.top > Math.max(0, window.innerHeight - 180);
    return nearRight && nearBottom;
  }

  function hasProductMediaContext(image) {
    let current = image;
    for (let depth = 0; depth < 7 && current && current !== document.body; depth += 1) {
      const text = normalizeText(current.innerText || current.textContent || '');
      if (text.length > 1800) {
        current = current.parentElement;
        continue;
      }
      if (extractMoneyTokens(text).length > 0 && !looksLikeSupportOrChromeText(text)) return true;
      if (/\b(item\s*id|sku|quantity|qty|cantidad|wake|shimano|sram|ztto|bike|bicycle|bicicleta)\b/i.test(text)) return true;
      current = current.parentElement;
    }
    return false;
  }

  function looksLikeCatalogImage(_imageUrl, rect) {
    const width = rect.width || 0;
    const height = rect.height || 0;
    const ratio = width / Math.max(height, 1);
    return width >= 45 && height >= 45 && ratio > 0.45 && ratio < 2.2;
  }

  function looksLikeSupportOrChromeText(text) {
    return /\b(need\s+help|help\s+center|customer\s+service|service\s+commitment|fast\s+delivery|return\s*&?\s*refund|order\s+completed|add\s+to\s+cart|cart)\b/i.test(text);
  }

  function mediaContextText(element) {
    let current = element;
    const chunks = [];
    for (let depth = 0; depth < 5 && current && current !== document.body; depth += 1) {
      chunks.push(current.getAttribute && current.getAttribute('aria-label'));
      chunks.push(current.getAttribute && current.getAttribute('class'));
      chunks.push(current.getAttribute && current.getAttribute('id'));
      const text = normalizeText(current.innerText || current.textContent || '');
      if (text.length <= 500) chunks.push(text);
      current = current.parentElement;
    }
    return chunks.filter(Boolean).join(' ').slice(0, 1200);
  }

  function dedupeTextKey(value) {
    return String(value || '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim()
      .slice(0, 48);
  }

  function findNearbyProductUrl(element) {
    const ownLink = element && element.closest
      ? element.closest('a[href*="/item/"],a[href*="itemId="],a[href*="productId="]')
      : null;
    if (ownLink && ownLink.href) return ownLink.href;

    const elementRect = element && element.getBoundingClientRect ? element.getBoundingClientRect() : null;
    let current = element ? element.parentElement : null;
    for (let depth = 0; depth < 6 && current && current !== document.body; depth += 1) {
      const link = findNearestLocalProductLink(current, elementRect);
      if (link) return link;
      current = current.parentElement;
    }
    return '';
  }

  function findNearestLocalProductLink(root, originRect) {
    if (!root || !root.querySelectorAll) return '';

    const rootRect = root.getBoundingClientRect ? root.getBoundingClientRect() : null;
    if (rootRect && rootRect.width * rootRect.height > (window.innerWidth * Math.max(window.innerHeight, 900) * 1.35)) {
      return '';
    }

    const anchors = Array.from(root.querySelectorAll('a[href*="/item/"],a[href*="itemId="],a[href*="productId="]'));
    if (anchors.length === 0) return '';

    let bestHref = '';
    let bestDistance = Number.POSITIVE_INFINITY;
    anchors.forEach((anchor) => {
      if (!anchor.href || !anchor.getBoundingClientRect) return;
      const rect = anchor.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return;

      const distance = localAnchorDistance(originRect, rect);
      if (distance > 260) return;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestHref = anchor.href;
      }
    });

    return bestHref;
  }

  function localAnchorDistance(originRect, candidateRect) {
    if (!originRect || !candidateRect) return Number.POSITIVE_INFINITY;

    const originCenterX = originRect.left + (originRect.width / 2);
    const originCenterY = originRect.top + (originRect.height / 2);
    const candidateCenterX = candidateRect.left + (candidateRect.width / 2);
    const candidateCenterY = candidateRect.top + (candidateRect.height / 2);
    const horizontalDistance = Math.abs(originCenterX - candidateCenterX);
    const verticalDistance = Math.abs(originCenterY - candidateCenterY);

    if (verticalDistance > 180 || horizontalDistance > 520) return Number.POSITIVE_INFINITY;
    return verticalDistance + (horizontalDistance * 0.35);
  }

  function parsePriceQuantityLine(line) {
    const text = String(line || '').trim();
    if (!/[x×]\s*\d/.test(text)) return null;
    if (/subtotal|total|shipping|env[ií]o|tax|iva|discount|descuento/i.test(text)) return null;

    const money = parseBestMoney(text);
    const quantityMatch = text.match(/[x×]\s*(\d+(?:[.,]\d+)?)/i);
    if (!money || !quantityMatch) return null;

    const quantity = parseLooseNumber(quantityMatch[1]);
    if (quantity <= 0 || quantity > 10000) return null;

    return {
      unitPrice: money.amount,
      quantity,
      currency: money.currency,
    };
  }

  function findLineItemContext(lines, priceLineIndex) {
    const candidates = [];

    for (let index = priceLineIndex - 1; index >= 0 && candidates.length < 5; index -= 1) {
      const line = cleanTitle(lines[index]);
      if (!isMeaningfulItemContextLine(line)) continue;
      candidates.unshift(line);
    }

    if (candidates.length === 0) return { title: '', variant: '' };

    const titleIndex = candidates.findIndex((line) => looksLikeProductTitle(line));
    if (titleIndex >= 0) {
      return {
        title: candidates[titleIndex],
        variant: candidates.slice(titleIndex + 1).filter(looksLikeVariantLine).join(' / '),
      };
    }

    if (candidates.length >= 2 && looksLikeVariantLine(candidates[candidates.length - 1])) {
      return {
        title: candidates[candidates.length - 2],
        variant: candidates[candidates.length - 1],
      };
    }

    return { title: candidates[candidates.length - 1], variant: '' };
  }

  function isMeaningfulItemContextLine(line) {
    if (!line || line.length < 3 || line.length > 220) return false;
    if (extractMoneyTokens(line).length > 0) return false;
    if (isDeliveryDateLine(line) || isRecommendationText(line)) return false;
    if (isPageChromeLine(line)) return false;
    if (/^(fast\s+delivery|add\s+to\s+cart|returns\/refunds|returns|refunds|subtotal|total|store|chat|contact|need\s+help\??|choice|sale)$/i.test(line)) return false;
    if (/^\d+(?:[.,]\d+)?\s*(?:pcs|pieces|unidades?)?$/i.test(line)) return false;
    return true;
  }

  function isStrongProductTitle(line) {
    if (!line || isPageChromeLine(line)) return false;
    return looksLikeProductTitle(line);
  }

  function looksLikeProductTitle(line) {
    if (!line) return false;
    if (isPageChromeLine(line)) return false;
    if (looksLikeVariantLine(line)) return false;
    return line.length > 28 || /\b(bicicleta|bike|bicycle|mountain|carretera|manillar|accessorios|accesorios|wake|shimano|sram|ztto)\b/i.test(line);
  }

  function isPageChromeLine(line) {
    return /\b(account|overview|orders|payment|returns?\/refunds?|feedback|settings|shipping\s+address|message\s+center|invite\s+friends|help\s+center|manage\s+reports|suggestion|ds\s+center|penalties|recalls|product\s+safety|mobile\s+app|service\s+commitment|fast\s+delivery|return\s*&?refund|order\s+placed|payment\s+completed|shipment\s+completed|order\s+completed|payment\s+method|receipt|add\s+to\s+cart|need\s+help|official\s+store|estimated\s+delivery\s+date)\b/i.test(line);
  }

  function isPageChromeContainer(text) {
    const value = normalizeText(text).toLowerCase();
    const markers = [
      /service\s+commitment/,
      /shipping\s+address/,
      /order\s+placed/,
      /payment\s+method/,
      /mobile\s+app/,
      /need\s+help/,
      /add\s+to\s+cart/,
      /account\s*\n\s*overview/,
    ];
    const markerCount = markers.reduce((count, pattern) => count + (pattern.test(value) ? 1 : 0), 0);
    return value.length > 650 && markerCount >= 2;
  }

  function isVisibleElement(element, orderScope) {
    if (!element || !element.getBoundingClientRect) return false;
    const rect = element.getBoundingClientRect();
    const y = rect.top + window.scrollY;
    if (rect.width <= 0 || rect.height <= 0) return false;
    if (orderScope && y >= orderScope.boundaryY - 4) return false;
    if (hasRecommendationAncestor(element)) return false;
    return true;
  }

  function dedupeExtractedItems(items) {
    const result = [];
    const duplicates = [];
    const explicitVariantKeys = new WeakMap();

    items.forEach((rawItem) => {
      const explicitVariantKey = explicitVariantIdentityKeyFromItem(rawItem);
      const item = withSupplierVariantIdentity(rawItem);
      explicitVariantKeys.set(item, explicitVariantKey);
      const duplicateIndex = result.findIndex((existing) => areLikelyDuplicateItems(
        existing,
        item,
        explicitVariantKeys.get(existing),
        explicitVariantKey,
      ));
      if (duplicateIndex < 0) {
        result.push(item);
        return;
      }

      duplicates.push({
        kept: debugItemSummary(result[duplicateIndex]),
        removed: debugItemSummary(item),
      });

      if (itemQualityScore(item) > itemQualityScore(result[duplicateIndex])) {
        result[duplicateIndex] = item;
      }
    });

    if (duplicates.length > 0) {
      // Resumen, no el volcado completo: cada duplicado traía la descripción
      // entera dos veces y una sola corrida emitía megabytes por la consola.
      // Ese caudal estrangula `debugPrint` del lado Flutter —los eventos del
      // ERP llegaban con minutos de retraso, haciendo ilegible cualquier
      // diagnóstico— y ralentiza el puente (2026-08-06).
      aeDebug('detail.items.deduplicated', {
        beforeCount: items.length,
        afterCount: result.length,
        duplicateCount: duplicates.length,
        keptSkus: result.map((item) => item.sku).filter(Boolean).slice(0, 12),
      }, 'warn');
    }

    return result;
  }

  function areLikelyDuplicateItems(first, second, firstExplicitVariantKey = '', secondExplicitVariantKey = '') {
    if (!first || !second) return false;
    const samePriceAndQuantity = roundMoney(first.unitPrice) === roundMoney(second.unitPrice)
      && roundMoney(first.total) === roundMoney(second.total)
      && Number(first.quantity || 0) === Number(second.quantity || 0);
    const firstTitle = dedupeTextKey(first.description);
    const secondTitle = dedupeTextKey(second.description);
    const sameSupplierItem = Boolean(
      (first.itemId && second.itemId && first.itemId === second.itemId)
      || (first.productUrl && second.productUrl
        && normalizeProductUrl(first.productUrl) === normalizeProductUrl(second.productUrl))
      || (first.sku && second.sku && first.sku === second.sku),
    );
    if (firstExplicitVariantKey && secondExplicitVariantKey
      && firstExplicitVariantKey !== secondExplicitVariantKey) return false;

    const firstVariantKey = variantIdentityKeyFromItem(first);
    const secondVariantKey = variantIdentityKeyFromItem(second);
    if (firstVariantKey && secondVariantKey && firstVariantKey !== secondVariantKey) return false;
    if (sameSupplierItem && samePriceAndQuantity && firstTitle === secondTitle) return true;

    const firstImageKey = imageIdentityKey(first.imageUrl);
    const secondImageKey = imageIdentityKey(second.imageUrl);
    const differentKnownImages = firstImageKey && secondImageKey && firstImageKey !== secondImageKey;

    if (first.itemId && second.itemId && first.itemId === second.itemId) {
      if ((firstVariantKey || secondVariantKey) && firstVariantKey !== secondVariantKey) return false;
      if (differentKnownImages && firstVariantKey !== secondVariantKey) return false;
      return true;
    }
    if (first.productUrl && second.productUrl && normalizeProductUrl(first.productUrl) === normalizeProductUrl(second.productUrl)) {
      if ((firstVariantKey || secondVariantKey) && firstVariantKey !== secondVariantKey) return false;
      if (differentKnownImages && firstVariantKey !== secondVariantKey) return false;
      return true;
    }

    if (!samePriceAndQuantity) return false;

    return isWeakItemDescription(first.description)
      || isWeakItemDescription(second.description)
      || firstTitle === secondTitle
      || shareMeaningfulTitleToken(firstTitle, secondTitle);
  }

  function isWeakItemDescription(description) {
    const value = cleanTitle(description);
    if (value.length < 30) return true;
    if (isPageChromeLine(value)) return true;
    return false;
  }

  function shareMeaningfulTitleToken(first, second) {
    const firstTokens = new Set(String(first || '').split(/\s+/).filter((token) => token.length >= 4));
    const secondTokens = String(second || '').split(/\s+/).filter((token) => token.length >= 4);
    return secondTokens.some((token) => firstTokens.has(token));
  }

  function variantIdentityKeyFromItem(item) {
    const explicitVariant = supplierVariantKey(item && item.variant);
    if (explicitVariant) return explicitVariant;
    const text = [
      item && item.description,
      item && item.sku,
    ].filter(Boolean).join(' ');
    return [
      extractVariantCodesFromText(text).join('|'),
      variantLabelKeyFromText(text),
    ].filter(Boolean).join('|');
  }

  function explicitVariantIdentityKeyFromItem(item) {
    const suppliedVariantKey = supplierVariantKey(item && item.variantKey);
    if (suppliedVariantKey && suppliedVariantKey !== 'default') {
      return suppliedVariantKey;
    }
    return supplierVariantKey(item && item.variant);
  }

  // A supplier listing plus its variant is the durable identity used by the
  // ERP alias table. Older extraction paths only embedded the variant in the
  // human description, leaving variantKey empty and forcing every re-import
  // through the expensive duplicate matcher again.
  function withSupplierVariantIdentity(item) {
    if (!item) return item;
    const explicit = cleanTitle(item.variant || '');
    const description = cleanTitle(item.description || '');
    const parenthetical = description
      .match(/\(([^()]{1,120})\)\s*$/);
    const variant = explicit || (parenthetical ? parenthetical[1] : '');
    const explicitLineTitle = cleanTitle(item.lineTitle || '');
    const inferredLineTitle = parenthetical && variant === parenthetical[1]
      ? cleanTitle(description.slice(0, parenthetical.index))
      : description;
    const lineTitle = explicitLineTitle || inferredLineTitle;
    const suppliedVariantKey = String(item.variantKey || '').trim();
    const immutableVariantKey = immutableSupplierVariantKey(suppliedVariantKey);
    const variantKey = immutableVariantKey
      || (suppliedVariantKey && (suppliedVariantKey !== 'default' || !variant)
      ? suppliedVariantKey
      : '')
      || supplierVariantKey(variant)
      || variantLabelKeyFromText(item.description)
      || supplierVariantKey(imageIdentityKey(item.imageUrl))
      || (suppliedVariantKey === 'default' ? 'default' : '')
      || 'default';
    return {
      ...item,
      lineTitle: lineTitle || null,
      variant,
      variantKey,
    };
  }

  function immutableSupplierVariantKey(value) {
    const match = String(value || '').trim().toLowerCase()
      .match(/^(sku|props):([a-z0-9:|._-]+)$/);
    if (!match || !match[2]) return '';
    return `${match[1]}:${match[2]}`.slice(0, 240);
  }

  function immutableVariantKeyFromApiLine(line) {
    if (!line) return '';
    const direct = [
      line.skuId,
      line.sku_id,
      line.orderLineSkuId,
      line.selectedSkuId,
    ].map((value) => String(value || '').trim())
      .find((value) => /^[a-z0-9._-]{2,180}$/i.test(value));
    if (direct) return `sku:${direct.toLowerCase()}`;

    const attributes = Array.isArray(line.skuAttrs) ? line.skuAttrs : [];
    const tuples = attributes.map((attribute) => {
      const propertyId = String((attribute && (
        attribute.propertyId
        || attribute.skuPropertyId
        || attribute.pid
      )) || '').trim();
      const valueId = String((attribute && (
        attribute.valueId
        || attribute.propertyValueId
        || attribute.skuPropertyValueId
        || attribute.vid
      )) || '').trim();
      if (!/^[a-z0-9._-]+$/i.test(propertyId)
          || !/^[a-z0-9._-]+$/i.test(valueId)) return '';
      return `${propertyId.toLowerCase()}:${valueId.toLowerCase()}`;
    }).filter(Boolean).sort();
    if (!tuples.length || tuples.length !== attributes.length) return '';
    return `props:${tuples.join('|')}`.slice(0, 240);
  }

  function supplierVariantKey(value) {
    return String(value || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 120);
  }

  function extractVariantCodesFromText(value) {
    return Array.from(new Set((String(value || '').match(/\b\d{8,14}\b/g) || [])
      .filter((code) => !/^100\d{10,18}$/.test(code))));
  }

  function variantLabelKeyFromText(value) {
    const text = cleanTitle(value).toLowerCase();
    const candidates = [];
    const parenthetical = text.match(/\(([^()]{2,90})\)\s*$/);
    if (parenthetical) candidates.push(parenthetical[1]);
    const dashVariant = text.match(/\s+-\s+([^\n]{2,90})$/);
    if (dashVariant) candidates.push(dashVariant[1]);
    candidates.push(text);

    for (const candidate of candidates) {
      const color = variantColorToken(candidate);
      if (color) return color;
    }

    return '';
  }

  function variantColorToken(value) {
    const normalized = String(value || '').toLowerCase().replace(/[^a-z\s]/g, ' ');
    const colors = [
      ['black', 'black', 'negro'],
      ['blue', 'blue', 'azul'],
      ['red', 'red', 'rojo'],
      ['golden', 'golden', 'gold', 'dorado'],
      ['purple', 'purple', 'morado'],
      ['green', 'green', 'verde'],
      ['white', 'white', 'blanco'],
      ['silver', 'silver', 'plateado'],
      ['gray', 'gray', 'grey', 'gris'],
      ['yellow', 'yellow', 'amarillo'],
      ['orange', 'orange', 'naranja'],
      ['pink', 'pink', 'rosado', 'rosa'],
    ];
    for (const [key, ...tokens] of colors) {
      if (tokens.some((token) => new RegExp(`\\b${token}\\b`, 'i').test(normalized))) return key;
    }
    return '';
  }

  function imageIdentityKey(imageUrl) {
    return normalizeImageUrl(imageUrl).replace(/[?#].*$/, '').replace(/_[0-9]+x[0-9]+\.(jpg|jpeg|png|webp)$/i, '.$1');
  }

  function itemQualityScore(item) {
    let score = 0;
    if (item.itemId) score += 30;
    if (item.productUrl) score += 20;
    if (item.imageUrl) score += 20;
    if (!isWeakItemDescription(item.description)) score += 10;
    score += Math.min(cleanTitle(item.description).length, 120) / 20;
    return score;
  }

  function normalizeProductUrl(url) {
    try {
      const parsed = new URL(url, location.href);
      return extractItemId(parsed.href) || parsed.pathname;
    } catch (_) {
      return String(url || '');
    }
  }

  function hashText(value) {
    let hash = 0;
    const text = String(value || '');
    for (let index = 0; index < text.length; index += 1) {
      hash = ((hash << 5) - hash) + text.charCodeAt(index);
      hash |= 0;
    }
    return hash;
  }

  function looksLikeVariantLine(line) {
    if (!line || line.length > 80) return false;
    if (/,/.test(line) && /\b(china|spain|france|united|usa|mexico|brasil|chile)\b/i.test(line)) return true;
    return /\b(red|blue|green|black|white|purple|golden|yellow|silver|grey|gray|rojo|azul|verde|negro|blanco|morado|dorado|amarillo|plateado|gris)\b/i.test(line);
  }

  function isCandidateProductAnchor(anchor, orderScope) {
    if (!/\/item\/|itemId=|productId=/i.test(anchor.href)) return false;
    const rect = anchor.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return false;
    const anchorY = rect.top + window.scrollY;
    if (anchorY >= orderScope.boundaryY - 4) return false;
    if (hasRecommendationAncestor(anchor)) return false;
    return true;
  }

  function extractItemId(url) {
    const patterns = [/\/item\/(\d+)\.html/i, /[?&](?:itemId|productId)=(\d+)/i, /\b(\d{10,})\b/];
    for (const pattern of patterns) {
      const match = String(url || '').match(pattern);
      if (match) return match[1];
    }
    return '';
  }

  function cleanTitle(value) {
    return String(value || '')
      .replace(/\s+/g, ' ')
      .replace(/^(view\s+details?|details?)\s*/i, '')
      .trim();
  }

  function imageAlt(anchor) {
    const image = anchor.querySelector('img');
    return image ? image.getAttribute('alt') || '' : '';
  }

  function findProductContainer(anchor, title, orderScope) {
    let current = anchor;
    let best = anchor;

    for (let depth = 0; depth < 8 && current && current !== document.body; depth += 1) {
      const rect = current.getBoundingClientRect();
      const currentY = rect.top + window.scrollY;
      if (currentY >= orderScope.boundaryY - 4 || hasRecommendationAncestor(current)) break;

      const text = normalizeText(current.innerText || '');
      const hasTitle = title && text.toLowerCase().includes(title.toLowerCase().slice(0, Math.min(24, title.length)));
      const hasMoney = extractMoneyTokens(text).length > 0;
      const reasonableSize = text.length < 1800;
      const insideOrderArea = !isRecommendationText(text);

      if (hasTitle && hasMoney && reasonableSize && insideOrderArea) best = current;
      current = current.parentElement;
    }

    return best;
  }

  function hasRecommendationAncestor(element) {
    let current = element;
    for (let depth = 0; depth < 8 && current && current !== document.body; depth += 1) {
      const text = normalizeText(current.innerText || current.textContent || '').trim();
      if (looksLikeRecommendationContainer(text)) return true;
      current = current.parentElement;
    }
    return false;
  }

  function looksLikeRecommendationContainer(text) {
    const normalized = String(text || '').replace(/\s+/g, ' ').trim();
    if (!normalized) return false;

    // Only trust recommendation markers when they appear as the local container
    // heading/lead text. Large ancestors like <body> often contain "More to love"
    // somewhere far below the real order items, which would otherwise exclude the
    // entire order from extraction.
    const lead = normalized.slice(0, 160);
    return /^(more\s+to\s+love|you\s+may\s+also\s+like|recommended\s+for\s+you|similar\s+items|tambi[eé]n\s+te\s+puede\s+gustar|m[aá]s\s+para\s+(?:amar|ti)|productos\s+relacionados|recomendad[oa]s?)(?:\b|\s|:|-)/i.test(lead);
  }

  function isRecommendationText(text) {
    return /\b(more\s+to\s+love|you\s+may\s+also\s+like|recommended\s+for\s+you|similar\s+items|tambi[eé]n\s+te\s+puede\s+gustar|m[aá]s\s+para\s+(?:amar|ti)|productos\s+relacionados|recomendad[oa]s?)\b/i.test(text);
  }

  function buildProductRowKey(element, title, quantity, total) {
    const rect = element.getBoundingClientRect();
    return [
      Math.round((rect.top + window.scrollY) / 8),
      Math.round((rect.left + window.scrollX) / 8),
      cleanTitle(title).toLowerCase().slice(0, 80),
      quantity,
      total,
    ].join('|');
  }

  function extractVariant(containerText, title) {
    const lines = containerText.split('\n').map((line) => line.trim()).filter(Boolean);
    const titleIndex = lines.findIndex((line) => cleanComparable(line).includes(cleanComparable(title).slice(0, 24)));
    const candidates = titleIndex >= 0 ? lines.slice(titleIndex + 1, titleIndex + 5) : lines.slice(1, 5);

    for (const line of candidates) {
      if (!line || line.length > 90) continue;
      if (extractMoneyTokens(line).length > 0) continue;
      if (/^(x\s*)?\d+(?:[.,]\d+)?$/i.test(line)) continue;
      if (/fast\s+delivery|estimated\s+delivery|shipping|env[ií]o|subtotal|total|store|chat|contact/i.test(line)) continue;
      return line.replace(/\s+/g, ' ');
    }

    return '';
  }

  function cleanComparable(value) {
    return String(value || '').toLowerCase().replace(/\s+/g, ' ').trim();
  }

  function extractQuantity(text) {
    const patterns = [
      /(?:qty|quantity|cantidad|cant\.?|pcs|pieces|unidades?)\s*[:x]?\s*(\d+(?:[.,]\d+)?)/i,
      /[x×]\s*(\d+(?:[.,]\d+)?)/i,
      /(\d+(?:[.,]\d+)?)\s*(?:pcs|pieces|unidades?)/i,
    ];

    for (const pattern of patterns) {
      const match = String(text || '').match(pattern);
      if (match) {
        const value = parseLooseNumber(match[1]);
        if (value > 0 && value < 10000) return value;
      }
    }

    return 1;
  }

  function parseBestMoney(text) {
    const tokens = extractMoneyTokens(text);
    if (tokens.length === 0) return null;
    return tokens.sort((a, b) => b.amount - a.amount)[0];
  }

  function parseFirstMoney(text) {
    const tokens = extractMoneyTokens(text);
    return tokens.length ? tokens[0] : null;
  }

  function nearestMoneyBeforeLabel(text) {
    const tokens = extractMoneyTokens(text);
    return tokens.length ? tokens[tokens.length - 1] : null;
  }

  function extractMoneyTokens(text) {
    const matches = String(text || '').match(/-?\s*(?:US\s*\$|USD|CLP\s*\$?|EUR|GBP|€|£|\$)\s*-?[\d.,]+|-?[\d.,]+\s*(?:USD|CLP|EUR|GBP)/gi) || [];
    return matches
      .map((raw) => ({ raw, currency: inferCurrency(raw), amount: parseMoneyAmount(raw) }))
        .filter((money) => Number.isFinite(money.amount));
  }

  function inferCurrency(value) {
    const upper = String(value || '').toUpperCase();
    if (/CLP/.test(upper)) return 'CLP';
    if (/EUR|€/.test(upper)) return 'EUR';
    if (/GBP|£/.test(upper)) return 'GBP';
    if (/\$\s*\d{1,3}(?:\.\d{3})+(?!\d)/.test(String(value || ''))) return 'CLP';
    if (/USD|US\s*\$|\$/.test(upper)) return 'USD';
    return '';
  }

  function parseMoneyAmount(value) {
    const cleaned = String(value || '').replace(/[^\d.,-]/g, '');
    return parseLooseNumber(cleaned);
  }

  function parseLooseNumber(value) {
    let cleaned = String(value || '').replace(/[^\d.,-]/g, '');
    if (!cleaned) return 0;

    const lastDot = cleaned.lastIndexOf('.');
    const lastComma = cleaned.lastIndexOf(',');

    if (lastDot >= 0 && lastComma >= 0) {
      if (lastComma > lastDot) cleaned = cleaned.replace(/\./g, '').replace(',', '.');
      else cleaned = cleaned.replace(/,/g, '');
    } else if (lastComma >= 0) {
      const decimals = cleaned.length - lastComma - 1;
      cleaned = decimals === 2 ? cleaned.replace(',', '.') : cleaned.replace(/,/g, '');
    } else if (lastDot >= 0) {
      const decimals = cleaned.length - lastDot - 1;
      if (decimals === 3 && cleaned.indexOf('.') === lastDot) cleaned = cleaned.replace(/\./g, '');
    }

    const parsed = Number.parseFloat(cleaned);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function resolveItemPrices(monies, quantity) {
    if (!monies || monies.length === 0) return { currency: '', unitPrice: 0, total: 0 };
    const sorted = [...monies].sort((a, b) => a.amount - b.amount);
    let unitPrice = sorted[0].amount;
    let total = sorted[sorted.length - 1].amount;

    if (quantity > 1) {
      const pair = findQtyPricePair(sorted, quantity);
      if (pair) {
        unitPrice = pair.unitPrice;
        total = pair.total;
      } else if (total === unitPrice) {
        total = roundMoney(unitPrice * quantity);
      }
    }

    return {
      currency: sorted[0].currency || '',
      unitPrice: roundMoney(unitPrice),
      total: roundMoney(total),
    };
  }

  function findQtyPricePair(monies, quantity) {
    for (const candidateUnit of monies) {
      const expected = roundMoney(candidateUnit.amount * quantity);
      const candidateTotal = monies.find((money) => Math.abs(money.amount - expected) < 0.05);
      if (candidateTotal) {
        return { unitPrice: candidateUnit.amount, total: candidateTotal.amount };
      }
    }
    return null;
  }

  function imageSrc(root) {
    const images = collectCandidateImageElements(root);
    const visibleImages = images
      .map((image) => {
        const rect = image.getBoundingClientRect();
        const imageUrl = imageUrlFromElement(image);
        const productUrl = findNearbyProductUrl(image);
        if (!imageUrl || rect.width < 20 || rect.height < 20) return null;
        if (isIgnoredMediaImage(image, rect, imageUrl, productUrl)) return null;
        return {
          image,
          imageUrl,
          area: rect.width * rect.height,
          score: mediaScore(image, rect, productUrl),
        };
      })
      .filter(Boolean)
      .sort((a, b) => (b.score - a.score) || (b.area - a.area));
    return visibleImages[0] ? visibleImages[0].imageUrl : '';
  }

  function sumItems(items) {
    return roundMoney(items.reduce((sum, item) => sum + (Number(item.total) || 0), 0));
  }

  function roundMoney(value) {
    return Math.round((Number(value) || 0) * 100) / 100;
  }

  function lastDigits(value, count) {
    return String(value || '').replace(/\D/g, '').slice(-count) || String(value || '').slice(-count);
  }

  function buildDefaultNotes(orderNumber) {
    const lines = ['Documento generado desde compra visible en AliExpress para carga OCR.'];
    if (orderNumber) lines.push(`Pedido AliExpress: ${orderNumber}.`);
    lines.push(`URL: ${location.href}`);
    return lines.join('\n');
  }
}());
