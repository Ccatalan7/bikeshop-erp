(function () {
  'use strict';

  const SOURCE = 'AliExpress';
  const CONTENT_VERSION = '0.3.32';

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
    await preloadOrderDetailContent();
    return extractOrder();
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
    const preload = await preloadOrdersListContent(filters || {});
    return { ...extractOrdersList(filters || {}), preload };
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
    visibleProductImageRects: getVisibleProductImageRects,
    getPageMetrics,
    scrollTo: scrollToPosition,
  };

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

  chrome.runtime.onMessage.addListener(onMessage);
  globalThis.__ALIEXPRESS_INVOICE_CONTENT_CLEANUP__ = () => {
    chrome.runtime.onMessage.removeListener(onMessage);
  };

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

    window.scrollTo(initialX, initialY);
    await sleep(70);
  }

  async function preloadOrdersListContent(filters = {}) {
    const initialX = window.scrollX;
    const initialY = window.scrollY;
    const maxLoadClicks = Math.min(24, Math.max(0, Number(filters.maxLoadClicks) || 16));
    let loadMoreClicks = 0;
    let scrollPasses = 0;
    let stuckClicks = 0;

    for (let cycle = 0; cycle <= maxLoadClicks; cycle += 1) {
      await traverseLoadedOrdersList(initialX);
      scrollPasses += 1;

      if (ordersListHasReachedDate(filters.exactDate || filters.fromDate)) break;

      const loadMoreButton = findOrdersListLoadMoreButton();
      if (!loadMoreButton || loadMoreClicks >= maxLoadClicks) break;

      const beforeCount = countOrderListNumbers();
      const beforeHeight = getDocumentScrollHeight();
      loadMoreButton.scrollIntoView({ block: 'center', inline: 'nearest' });
      await sleep(120);
      loadMoreButton.click();
      loadMoreClicks += 1;
      await sleep(900);

      const afterCount = countOrderListNumbers();
      const afterHeight = getDocumentScrollHeight();
      if (afterCount <= beforeCount && afterHeight <= beforeHeight + 24) {
        stuckClicks += 1;
        if (stuckClicks >= 2) break;
      } else {
        stuckClicks = 0;
      }
    }

    window.scrollTo(initialX, initialY);
    await sleep(90);
    return { loadMoreClicks, scrollPasses };
  }

  async function traverseLoadedOrdersList(initialX) {
    const viewportHeight = window.innerHeight || 800;
    const maxY = Math.max(0, getDocumentScrollHeight() - viewportHeight);
    const startY = window.scrollY;
    const maxTraversalY = Math.min(maxY, startY + Math.max(9000, viewportHeight * 8));
    const step = Math.max(520, Math.floor(viewportHeight * 0.78));

    for (let y = startY; y <= maxTraversalY; y += step) {
      window.scrollTo(initialX, y);
      await sleep(120);
    }
  }

  function getDocumentScrollHeight() {
    return Math.max(
      document.documentElement ? document.documentElement.scrollHeight : 0,
      document.body ? document.body.scrollHeight : 0,
    );
  }

  function countOrderListNumbers() {
    const text = normalizeText(document.body ? document.body.innerText : '');
    const numbers = new Set();
    const patterns = [
      /\border\s*(?:id|number|no\.?)\s*[:#]?\s*(\d{8,})/gi,
      /\bpedido\s*(?:n[°o.]?|numero|id)?\s*[:#]?\s*(\d{8,})/gi,
    ];
    patterns.forEach((pattern) => {
      let match;
      while ((match = pattern.exec(text)) !== null) numbers.add(match[1]);
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

  function findOrdersListLoadMoreButton() {
    const candidates = Array.from(document.querySelectorAll('button,[role="button"],a,div,span'));
    return candidates
      .map((element) => ({ element, score: ordersListLoadMoreScore(element) }))
      .filter((entry) => entry.score > 0)
      .sort((a, b) => b.score - a.score)[0]?.element || null;
  }

  function ordersListLoadMoreScore(element) {
    if (!element || !element.getBoundingClientRect) return 0;
    const rect = element.getBoundingClientRect();
    const style = window.getComputedStyle ? window.getComputedStyle(element) : null;
    if (rect.width < 60 || rect.height < 24 || rect.bottom < 0 || rect.top > (window.innerHeight || 800) + 300) return 0;
    if (style && (style.display === 'none' || style.visibility === 'hidden' || style.pointerEvents === 'none')) return 0;
    if (element.disabled || element.getAttribute('aria-disabled') === 'true') return 0;
    if (hasFloatingUiAncestor(element) || hasRecommendationAncestor(element)) return 0;

    const text = normalizeText(element.innerText || element.textContent || element.getAttribute('aria-label') || '').trim();
    const compact = text.toLowerCase().replace(/\s+/g, ' ');
    if (!compact || compact.length > 80) return 0;
    if (/order\s*details|detalles\s+del\s+pedido|add\s+to\s+cart|remove|copy|need\s+help/i.test(compact)) return 0;

    let score = 0;
    if (/^view\s+orders?$/.test(compact)) score += 100;
    if (/^view\s+more\s+orders?$/.test(compact)) score += 95;
    if (/^load\s+more\s+orders?$/.test(compact)) score += 95;
    if (/^show\s+more\s+orders?$/.test(compact)) score += 90;
    if (/^(view|show|load)\s+more$/.test(compact)) score += 70;
    if (/\b(ver|mostrar|cargar)\b.*\b(pedidos|ordenes|órdenes)\b/i.test(compact)) score += 90;
    if (!score) return 0;
    score += Math.max(0, rect.top + window.scrollY) / 100000;
    if (element.matches('button,[role="button"],a')) score += 5;
    return score;
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
          description: orderNumber ? `AliExpress order ${orderNumber}` : 'AliExpress order',
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
      orderDate: orderDate || new Date().toISOString().slice(0, 10),
      currency: 'CLP',
      subtotal: totals.subtotal || null,
      shipping: totals.shipping || null,
      tax: totals.tax || null,
      discount: totals.discount || null,
      total: totals.total || sumItems(resolvedItems),
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
    const orders = allOrders
      .filter((order) => isDateInRange(order.orderDate, fromDate, toDate));
    const undatedCount = allOrders.filter((order) => !order.orderDate).length;

    if (cards.length === 0) {
      warnings.push('No se encontraron tarjetas de orden en la lista actual. Abre Account > Orders y deja cargadas las ordenes visibles.');
    }
    if (cards.length > 0 && orders.length === 0) {
      warnings.push('Se encontraron ordenes, pero ninguna calza con el rango de fechas seleccionado.');
    }
    if (undatedCount > 0) {
      warnings.push(`${undatedCount} orden(es) no tenian fecha de compra parseable en la lista; se incluyeron para revision manual.`);
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

  function collectOrderListCards() {
    const byOrder = new Map();
    Array.from(document.querySelectorAll('article,section,li,div'))
      .forEach((element) => {
        if (!element || !element.getBoundingClientRect) return;
        const text = normalizeText(element.innerText || element.textContent || '').trim();
        if (!text || text.length < 40 || text.length > 3600) return;
        const orderNumber = extractOrderListNumber(text);
        if (!orderNumber) return;

        const card = findOrderListCard(element, orderNumber);
        if (!card) return;
        const cardText = normalizeText(card.innerText || card.textContent || '').trim();
        const candidate = { element: card, text: cardText, orderNumber, score: orderListCardScore(card, cardText) };
        const existing = byOrder.get(orderNumber);
        if (!existing || candidate.score > existing.score) byOrder.set(orderNumber, candidate);
      });

    return Array.from(byOrder.values())
      .sort((a, b) => cardPageY(a.element) - cardPageY(b.element))
      .map((entry) => entry.element);
  }

  function findOrderListCard(seed, orderNumber) {
    let current = seed;
    let best = null;
    for (let depth = 0; depth < 9 && current && current !== document.body; depth += 1) {
      if (!current.getBoundingClientRect) {
        current = current.parentElement;
        continue;
      }
      const rect = current.getBoundingClientRect();
      const text = normalizeText(current.innerText || current.textContent || '').trim();
      const containsOrder = text.includes(orderNumber);
      const hasDate = /\border\s*date\b|\bfecha\b|\bpedido\s+efectuado\b/i.test(text);
      const hasTotal = /\btotal\s*:/i.test(text) || /\btotal\b[^\n]{0,30}(?:CLP\s*)?\$\s*[\d.,]+/i.test(text);
      const reasonable = rect.width >= 360 && rect.height >= 70 && text.length <= 3600;
      if (containsOrder && hasDate && hasTotal && reasonable && !isRecommendationText(text)) {
        best = current;
      }
      current = current.parentElement;
    }
    return best;
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
    const orderNumber = extractOrderListNumber(text);
    if (!orderNumber) return null;

    const orderDate = extractOrderListDate(lines);
    const totalMoney = extractOrderListTotal(lines, text);
    const detailUrl = findOrderListDetailUrl(card, orderNumber) || location.href;
    const items = extractOrderListItems(card);
    const resolvedItems = items.length > 0 ? items : [buildOrderListSummaryItem(card, orderNumber, totalMoney)];
    const total = totalMoney ? totalMoney.amount : sumItems(resolvedItems);

    return {
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
  }

  function extractOrderListNumber(text) {
    const patterns = [
      /\border\s*(?:id|number|no\.?)\s*[:#]?\s*(\d{8,})/i,
      /\bpedido\s*(?:n[°o.]?|numero|id)?\s*[:#]?\s*(\d{8,})/i,
    ];
    for (const pattern of patterns) {
      const match = String(text || '').match(pattern);
      if (match) return match[1];
    }
    return '';
  }

  function extractOrderListDate(lines) {
    const dateLine = lines.find((line) => /\border\s*date\b|\bfecha\s*(?:del\s*)?pedido\b|\bpedido\s+efectuado\b/i.test(line) && !isDeliveryDateLine(line));
    if (dateLine) {
      const afterLabel = dateLine.replace(/^.*?(?:order\s*date|fecha\s*(?:del\s*)?pedido|pedido\s+efectuado)\s*[:\-]?\s*/i, '');
      return parseDateString(afterLabel) || parseDateString(dateLine);
    }
    return extractDate(lines);
  }

  function extractOrderListTotal(lines, text) {
    const totalLine = lines.find((line) => /\btotal\s*:/i.test(line))
      || lines.find((line) => /\btotal\b/i.test(line) && extractMoneyTokens(line).length > 0);
    return parseBestMoney(totalLine || text);
  }

  function findOrderListDetailUrl(card, orderNumber) {
    const anchors = Array.from(card.querySelectorAll('a[href]'));
    const detailAnchor = anchors.find((anchor) => /order.*detail|detail.*order|detalles/i.test(anchor.innerText || anchor.textContent || anchor.href))
      || anchors.find((anchor) => String(anchor.href || '').includes(orderNumber))
      || anchors.find((anchor) => /order.*detail|orderId|order_id|orderIdList/i.test(anchor.href || ''));
    return detailAnchor && detailAnchor.href ? detailAnchor.href : '';
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

    const result = [];
    const seen = new Set();
    candidates
      .sort((a, b) => a._y - b._y || a._x - b._x)
      .forEach((item) => {
        const key = [
          normalizeProductUrl(item.productUrl),
          item.itemId || '',
          dedupeTextKey(item.description),
          imageIdentityKey(item.imageUrl),
          item.total,
          item.quantity,
        ].join('|');
        if (seen.has(key)) return;
        seen.add(key);
        const { _y, _x, ...publicItem } = item;
        result.push(publicItem);
      });
    return result.slice(0, 20);
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
      description,
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
      description: title,
      quantity: 1,
      unitPrice: total,
      total,
      productUrl: findOrderListDetailUrl(card, orderNumber) || location.href,
      itemId: '',
      imageUrl: imageSrc(card) || '',
    };
  }

  function isDateInRange(date, fromDate, toDate) {
    if (!date) return true;
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
    const labelPattern = /(order\s*(date|time)|placed\s*on|paid\s*on|fecha\s*(del\s*pedido)?|pedido\s*realizado)\s*[:\-]?\s*(.+)/i;

    for (const line of lines.slice(0, 80)) {
      if (isDeliveryDateLine(line)) continue;
      const labelMatch = line.match(labelPattern);
      if (labelMatch) {
        const parsed = parseDateString(labelMatch[4] || labelMatch[0]);
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
      return toIsoDate(year, Number(match[2]), Number(match[1]));
    }

    match = text.match(/\b([A-Za-z.]+)\s+(\d{1,2}),?\s+(20\d{2})\b/);
    if (match) return toIsoDate(Number(match[3]), monthNumber(match[1]), Number(match[2]));

    match = text.match(/\b(\d{1,2})\s+([A-Za-z.]+)\s+(20\d{2})\b/);
    if (match) return toIsoDate(Number(match[3]), monthNumber(match[2]), Number(match[1]));

    match = text.match(/\b(\d{1,2})\s+(?:de\s+)?([A-Za-z.]+)\s+(?:de\s+)?(20\d{2})\b/i);
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

    const fields = [
      { key: 'subtotal', pattern: /(subtotal|items\s*total|productos)/i },
      { key: 'shipping', pattern: /(shipping|env.?o|entrega|flete)/i },
      { key: 'tax', pattern: /(tax|iva|impuesto)/i },
      { key: 'discount', pattern: /(discount|descuento|coupon|cupon)/i },
      { key: 'total', pattern: /\b(order\s*total|grand\s*total|amount\s*paid|payment\s*total|total\s*paid|total\s*del\s*pedido|total)\b/i },
    ];

    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      for (const field of fields) {
        if (!field.pattern.test(line)) continue;
        const money = parseBestMoney(line) || parseBestMoney(`${line} ${lines[index + 1] || ''}`);
        if (!money) continue;
        result[field.key] = money.amount;
        result.currency = result.currency || money.currency;
      }
    }

    const totalsTable = extractTotalsTable(lines);
    Object.entries(totalsTable).forEach(([key, money]) => {
      if (money) {
        result[key] = money.amount;
        result.currency = result.currency || money.currency;
      }
    });

    if (!result.total) {
      const tail = lines.slice(Math.max(0, lines.length - 80));
      const candidates = tail.map(parseBestMoney).filter(Boolean);
      candidates.sort((a, b) => b.amount - a.amount);
      if (candidates[0]) {
        result.total = candidates[0].amount;
        result.currency = result.currency || candidates[0].currency;
      }
    }

    if (!result.shipping && result.subtotal && result.total) {
      const derivedShipping = roundMoney(result.total - result.subtotal - (result.tax || 0) + (result.discount || 0));
      if (derivedShipping > 0) result.shipping = derivedShipping;
    }

    return result;
  }

  function extractTotalsTable(lines) {
    const labelSpecs = [
      { key: 'subtotal', pattern: /^(subtotal|items\s*total|productos)$/i },
      { key: 'shipping', pattern: /^(shipping|env.?o|entrega|flete)$/i },
      { key: 'tax', pattern: /^(tax|iva|impuesto)$/i },
      { key: 'discount', pattern: /^(discount|descuento|coupon|cupon)$/i },
      { key: 'total', pattern: /^(total|order\s*total|grand\s*total|amount\s*paid|payment\s*total|total\s*paid|total\s*del\s*pedido)$/i },
    ];

    const startIndex = lines.findIndex((line) => /^(subtotal|items\s*total|productos)$/i.test(line.trim()));
    if (startIndex < 0) return {};

    const tail = lines.slice(startIndex, Math.min(lines.length, startIndex + 24));
    const labels = [];
    const monies = [];

    tail.forEach((line) => {
      const trimmed = line.trim();
      const labelSpec = labelSpecs.find((spec) => spec.pattern.test(trimmed));
      if (labelSpec) labels.push(labelSpec.key);

      const money = parseBestMoney(trimmed);
      if (money) monies.push(money);
    });

    if (labels.length < 2 || monies.length < labels.length) return {};

    const result = {};
    labels.forEach((label, index) => {
      if (!result[label] && monies[index]) result[label] = monies[index];
    });
    return result;
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
        description,
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
        description,
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
        description,
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
        description,
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

    items.forEach((item) => {
      const imageKey = item.imageUrl ? normalizeImageUrl(item.imageUrl).replace(/[?#].*$/, '') : '';
      const titleKey = dedupeTextKey(item.description);
      const rowKey = item._visualRowY ? Math.round(item._visualRowY / 18) : result.length;
      const key = item.itemId
        ? `id:${item.itemId}:${item.unitPrice}:${item.quantity}:${titleKey}:${imageKey || rowKey}`
        : `${titleKey}|${item.unitPrice}|${item.quantity}|${imageKey || rowKey}`;
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
      description,
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
        description,
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

    items.forEach((item) => {
      const duplicateIndex = result.findIndex((existing) => areLikelyDuplicateItems(existing, item));
      if (duplicateIndex < 0) {
        result.push(item);
        return;
      }

      if (itemQualityScore(item) > itemQualityScore(result[duplicateIndex])) {
        result[duplicateIndex] = item;
      }
    });

    return result;
  }

  function areLikelyDuplicateItems(first, second) {
    if (!first || !second) return false;
    const firstVariantKey = variantIdentityKeyFromItem(first);
    const secondVariantKey = variantIdentityKeyFromItem(second);
    if (firstVariantKey && secondVariantKey && firstVariantKey !== secondVariantKey) return false;

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

    const samePriceAndQuantity = roundMoney(first.unitPrice) === roundMoney(second.unitPrice)
      && roundMoney(first.total) === roundMoney(second.total)
      && Number(first.quantity || 0) === Number(second.quantity || 0);
    if (!samePriceAndQuantity) return false;

    const firstTitle = dedupeTextKey(first.description);
    const secondTitle = dedupeTextKey(second.description);
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
    const text = [
      item && item.description,
      item && item.sku,
    ].filter(Boolean).join(' ');
    return [
      extractVariantCodesFromText(text).join('|'),
      variantLabelKeyFromText(text),
    ].filter(Boolean).join('|');
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

  function extractMoneyTokens(text) {
    const matches = String(text || '').match(/(?:US\s*\$|USD|CLP\s*\$?|EUR|GBP|€|£|\$)\s*-?[\d.,]+|-?[\d.,]+\s*(?:USD|CLP|EUR|GBP)/gi) || [];
    return matches
      .map((raw) => ({ raw, currency: inferCurrency(raw), amount: parseMoneyAmount(raw) }))
      .filter((money) => Number.isFinite(money.amount) && money.amount >= 0);
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