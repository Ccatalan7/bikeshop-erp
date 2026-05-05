(function () {
  'use strict';

  const STORAGE_PREFIX = 'aliexpressInvoiceDraft:';
  const GEMINI_KEY_STORAGE = 'aliexpressInvoiceGeminiApiKey';
  const GEMINI_MODELS = [
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-flash-latest',
  ];
  const CONTENT_SCRIPT_VERSION = '0.3.24';
  const imageDimensionCache = new Map();
  const state = {
    items: [],
    pageUrl: '',
    pageTitle: '',
    extractedAt: '',
    warnings: [],
    subtotal: null,
    shipping: null,
    tax: null,
    discount: null,
    lastDebug: null,
  };

  const el = {
    extractButton: document.getElementById('extractButton'),
    addItemButton: document.getElementById('addItemButton'),
    generateButton: document.getElementById('generateButton'),
    downloadJsonButton: document.getElementById('downloadJsonButton'),
    copyTextButton: document.getElementById('copyTextButton'),
    aiExtractButton: document.getElementById('aiExtractButton'),
    saveGeminiKeyButton: document.getElementById('saveGeminiKeyButton'),
    geminiApiKey: document.getElementById('geminiApiKey'),
    status: document.getElementById('status'),
    supplierName: document.getElementById('supplierName'),
    supplierTaxId: document.getElementById('supplierTaxId'),
    orderNumber: document.getElementById('orderNumber'),
    orderDate: document.getElementById('orderDate'),
    currency: document.getElementById('currency'),
    total: document.getElementById('total'),
    subtotal: document.getElementById('subtotal'),
    shipping: document.getElementById('shipping'),
    notes: document.getElementById('notes'),
    itemsList: document.getElementById('itemsList'),
  };

  document.addEventListener('DOMContentLoaded', () => {
    setDefaultDate();
    loadGeminiKey();
    renderItems();
  });

  el.extractButton.addEventListener('click', extractCurrentPage);
  el.aiExtractButton.addEventListener('click', extractCurrentVisibleAreaWithAi);
  el.saveGeminiKeyButton.addEventListener('click', saveGeminiKey);
  el.addItemButton.addEventListener('click', () => {
    state.items.push(createEmptyItem());
    renderItems();
    recalculateTotalIfNeeded();
  });
  el.generateButton.addEventListener('click', generateInvoice);
  el.downloadJsonButton.addEventListener('click', downloadJson);
  el.copyTextButton.addEventListener('click', copyOcrText);

  el.itemsList.addEventListener('input', (event) => {
    const row = event.target.closest('[data-index]');
    if (!row) return;
    const index = Number(row.dataset.index);
    const field = event.target.dataset.field;
    if (!field || !state.items[index]) return;

    const rawValue = event.target.value;
    state.items[index][field] = ['quantity', 'unitPrice', 'total'].includes(field)
      ? toNumber(rawValue)
      : rawValue;

    if (field === 'quantity' || field === 'unitPrice') {
      state.items[index].total = roundMoney((state.items[index].quantity || 0) * (state.items[index].unitPrice || 0));
      const totalInput = row.querySelector('[data-field="total"]');
      if (totalInput) totalInput.value = String(state.items[index].total || '');
    }

    recalculateTotalIfNeeded();
  });

  el.itemsList.addEventListener('click', (event) => {
    if (!event.target.matches('[data-remove-index]')) return;
    const index = Number(event.target.dataset.removeIndex);
    state.items.splice(index, 1);
    renderItems();
    recalculateTotalIfNeeded();
  });

  async function extractCurrentPage() {
    setStatus('Extrayendo datos visibles de AliExpress...', 'neutral');
    el.extractButton.disabled = true;

    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab || !tab.id) throw new Error('No se encontro una pestana activa.');
      if (!/^https:\/\/([^/]+\.)?aliexpress\.com\//i.test(tab.url || '')) {
        throw new Error('Abre una pagina de AliExpress antes de extraer datos.');
      }

      await ensureFreshContentBridge(tab.id);
      const response = await sendExtractionMessage(tab.id);
      if (!response || !response.ok) {
        throw new Error(response && response.error ? response.error : 'No se pudo extraer la orden.');
      }

      applyOrder(response.order);
      const warningText = response.order.warnings && response.order.warnings.length
        ? ` ${response.order.warnings.join(' ')}`
        : '';
      setStatus(`Datos extraidos. Revisa los campos antes de generar el PDF.${warningText}`, response.order.warnings && response.order.warnings.length ? 'warning' : 'success');
    } catch (error) {
      setStatus(error.message || String(error), 'error');
    } finally {
      el.extractButton.disabled = false;
    }
  }

  async function sendExtractionMessage(tabId) {
    return executeContentCommand(tabId, 'extract');
  }

  async function ensureFreshContentBridge(tabId) {
    await chrome.scripting.executeScript({ target: { tabId }, files: ['content.js'] });
    const response = await executeContentCommand(tabId, 'version');
    if (!response || !response.ok || response.version !== CONTENT_SCRIPT_VERSION) {
      throw new Error('No se pudo cargar el extractor actualizado en la pagina de AliExpress.');
    }
  }

  async function executeContentCommand(tabId, command, payload) {
    const results = await chrome.scripting.executeScript({
      target: { tabId },
      func: async ({ command: requestedCommand, payload: requestedPayload }) => {
        const bridge = globalThis.__ALIEXPRESS_INVOICE_BRIDGE__;
        if (!bridge) {
          return { ok: false, error: 'AliExpress extractor bridge unavailable.' };
        }

        try {
          switch (requestedCommand) {
            case 'version':
              return { ok: true, version: bridge.version || '' };
            case 'extract':
              return { ok: true, order: await bridge.extractOrder() };
            case 'productMediaRows':
              return { ok: true, media: await bridge.extractProductMediaRows() };
            case 'visibleProductImageRects':
              return { ok: true, rects: bridge.visibleProductImageRects ? bridge.visibleProductImageRects() : [] };
            case 'pageMetrics':
              return { ok: true, metrics: bridge.getPageMetrics() };
            case 'scrollTo':
              return { ok: true, ...(await bridge.scrollTo(requestedPayload && requestedPayload.y)) };
            default:
              return { ok: false, error: `Unknown content command: ${requestedCommand}` };
          }
        } catch (error) {
          return {
            ok: false,
            error: error && error.message ? error.message : String(error),
          };
        }
      },
      args: [{ command, payload: payload || null }],
    });

    return results && results[0] ? (results[0].result || null) : null;
  }

  async function loadGeminiKey() {
    try {
      const stored = await chrome.storage.local.get(GEMINI_KEY_STORAGE);
      el.geminiApiKey.value = stored[GEMINI_KEY_STORAGE] || '';
    } catch (_error) {
      el.geminiApiKey.value = '';
    }
  }

  async function saveGeminiKey() {
    const apiKey = el.geminiApiKey.value.trim();
    if (!apiKey) {
      await chrome.storage.local.remove(GEMINI_KEY_STORAGE);
      setStatus('Clave Gemini borrada.', 'neutral');
      return;
    }

    await chrome.storage.local.set({ [GEMINI_KEY_STORAGE]: apiKey });
    setStatus('Clave Gemini guardada localmente en Chrome.', 'success');
  }

  async function extractCurrentVisibleAreaWithAi() {
    const apiKey = el.geminiApiKey.value.trim();
    if (!apiKey) {
      setStatus('Pega tu Gemini API key y pulsa Guardar antes de usar AI OCR.', 'error');
      return;
    }

    setStatus('Leyendo DOM y preparando captura completa para AI OCR...', 'neutral');
    el.aiExtractButton.disabled = true;
    el.extractButton.disabled = true;

    try {
      await chrome.storage.local.set({ [GEMINI_KEY_STORAGE]: apiKey });
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab || !tab.id) throw new Error('No se encontro una pestana activa.');
      if (!/^https:\/\/([^/]+\.)?aliexpress\.com\//i.test(tab.url || '')) {
        throw new Error('Abre una pagina de AliExpress antes de usar AI OCR.');
      }

      await ensureFreshContentBridge(tab.id);
      let domOrder = null;
      let productMediaRows = [];
      try {
        const response = await sendExtractionMessage(tab.id);
        if (response && response.ok) domOrder = response.order;
      } catch (_error) {
        domOrder = null;
      }
      try {
        const mediaResponse = await executeContentCommand(tab.id, 'productMediaRows');
        if (mediaResponse && mediaResponse.ok && Array.isArray(mediaResponse.media)) {
          productMediaRows = mediaResponse.media;
        }
      } catch (_error) {
        productMediaRows = [];
      }

      if (productMediaRows.length > 0) {
        domOrder = {
          ...(domOrder || {}),
          media: mergeMediaRows(productMediaRows, domOrder && Array.isArray(domOrder.media) ? domOrder.media : []),
        };
      }

      const screenshots = await captureFullPageScreenshots(tab);
      if (!screenshots.length) throw new Error('No se pudo capturar la pagina.');
      setStatus(`Enviando ${screenshots.length} captura(s) a Gemini...`, 'neutral');

      const aiOrder = await extractInvoiceFromScreenshots(apiKey, screenshots, domOrder);
      applyAiOrder(aiOrder, domOrder);
      const orderCropDebug = hydrateMissingOrderCropImages(screenshots);
      const productImageDebug = await hydrateMissingProductImages(domOrder);
      const linkedImages = state.items.filter((item) => item.imageUrl).length;
      const statusType = linkedImages === state.items.length ? 'success' : 'warning';
      setStatus(`AI OCR aplicado (${screenshots.length} captura(s), ${state.items.length} linea(s), imagenes ${linkedImages}/${state.items.length}). Revisa antes de generar el PDF.`, statusType);
      state.lastDebug = {
        contentVersion: CONTENT_SCRIPT_VERSION,
        productMediaRows: productMediaRows.slice(0, 8),
        domItems: (domOrder && Array.isArray(domOrder.items) ? domOrder.items : []).slice(0, 8),
        domMedia: (domOrder && Array.isArray(domOrder.media) ? domOrder.media : []).slice(0, 8),
        orderPageCrops: orderCropDebug,
        productPageImages: productImageDebug,
        resultItems: state.items.slice(0, 8).map(toDebugItem),
      };
      renderDebug(state.lastDebug);
    } catch (error) {
      renderDebug(null);
      setStatus(error.message || String(error), 'error');
    } finally {
      el.aiExtractButton.disabled = false;
      el.extractButton.disabled = false;
    }
  }

  async function captureFullPageScreenshots(tab) {
    const metrics = await executeContentCommand(tab.id, 'pageMetrics');
    if (!metrics || !metrics.ok) throw new Error('No se pudieron leer metricas de la pagina.');

    const { innerHeight, scrollHeight } = metrics.metrics;
    const viewport = Math.max(400, innerHeight || 800);
    const totalHeight = Math.max(viewport, scrollHeight || viewport);
    // Overlap each screenshot by ~12% so no item gets cut at the seam.
    const step = Math.max(300, Math.floor(viewport * 0.88));
    const positions = [];
    for (let y = 0; y < totalHeight; y += step) {
      positions.push(y);
      if (y + viewport >= totalHeight) break;
    }
    if (positions.length === 0) positions.push(0);
    // Cap to avoid Gemini payload explosions / captureVisibleTab rate limits.
    const MAX_SHOTS = 8;
    const trimmed = positions.slice(0, MAX_SHOTS);

    const shots = [];
    for (let i = 0; i < trimmed.length; i++) {
      const y = trimmed[i];
      const scrollResp = await executeContentCommand(tab.id, 'scrollTo', { y });
      if (!scrollResp || !scrollResp.ok) continue;
      const rectResp = await executeContentCommand(tab.id, 'visibleProductImageRects').catch(() => null);
      // captureVisibleTab is rate-limited (~2/s). 600ms is comfortably safe.
      await sleep(i === 0 ? 250 : 650);
      try {
        const dataUrl = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'png' });
        const base64 = String(dataUrl || '').split(',')[1];
        if (base64) {
          const imageCrops = rectResp && rectResp.ok && Array.isArray(rectResp.rects)
            ? await cropVisibleProductImages(dataUrl, rectResp.rects, metrics.metrics)
            : [];
          shots.push({ y, base64, imageCrops });
        }
      } catch (error) {
        // If we hit the rate limit, wait and retry once.
        await sleep(900);
        try {
          const dataUrl = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'png' });
          const base64 = String(dataUrl || '').split(',')[1];
          if (base64) {
            const imageCrops = rectResp && rectResp.ok && Array.isArray(rectResp.rects)
              ? await cropVisibleProductImages(dataUrl, rectResp.rects, metrics.metrics)
              : [];
            shots.push({ y, base64, imageCrops });
          }
        } catch (_again) {
          // skip this slice
        }
      }
      setStatus(`Capturando pagina (${shots.length}/${trimmed.length})...`, 'neutral');
    }

    // Restore scroll to top so the user does not feel jumpy.
    await executeContentCommand(tab.id, 'scrollTo', { y: 0 });
    return shots;
  }

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  async function cropVisibleProductImages(dataUrl, rects, metrics) {
    if (!rects || rects.length === 0) return [];
    const image = await loadImage(dataUrl);
    const scaleX = image.naturalWidth / Math.max(1, Number(metrics && metrics.innerWidth) || image.naturalWidth);
    const scaleY = image.naturalHeight / Math.max(1, Number(metrics && metrics.innerHeight) || image.naturalHeight);

    return rects.map((rect) => {
      const sx = Math.max(0, Math.floor(Number(rect.left || 0) * scaleX));
      const sy = Math.max(0, Math.floor(Number(rect.top || 0) * scaleY));
      const sw = Math.min(image.naturalWidth - sx, Math.max(1, Math.ceil(Number(rect.width || 1) * scaleX)));
      const sh = Math.min(image.naturalHeight - sy, Math.max(1, Math.ceil(Number(rect.height || 1) * scaleY)));
      if (sw <= 1 || sh <= 1) return null;
      const canvas = document.createElement('canvas');
      canvas.width = sw;
      canvas.height = sh;
      const context = canvas.getContext('2d');
      context.drawImage(image, sx, sy, sw, sh, 0, 0, sw, sh);
      const finalCanvas = rect.source === 'visual-row-approximation'
        ? tightenApproximateProductCrop(canvas)
        : canvas;
      return {
        dataUrl: finalCanvas.toDataURL('image/png'),
        pageY: rect.pageY || 0,
        pageX: rect.pageX || 0,
        variantCodes: rect.variantCodes || [],
        itemId: rect.itemId || '',
        imageUrl: rect.imageUrl || '',
        productUrl: rect.productUrl || '',
        source: rect.source || '',
        rowText: rect.rowText || '',
        width: finalCanvas.width,
        height: finalCanvas.height,
      };
    }).filter(Boolean);
  }

  function tightenApproximateProductCrop(sourceCanvas) {
    const sourceContext = sourceCanvas.getContext('2d', { willReadFrequently: true });
    if (!sourceContext) return sourceCanvas;

    const width = sourceCanvas.width;
    const height = sourceCanvas.height;
    if (width < 30 || height < 30) return sourceCanvas;

    const pixels = sourceContext.getImageData(0, 0, width, height).data;
    const background = averageCornerColor(pixels, width, height);
    const foreground = new Uint8Array(width * height);

    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const index = (y * width + x) * 4;
        const alpha = pixels[index + 3];
        if (alpha < 24) continue;

        const red = pixels[index];
        const green = pixels[index + 1];
        const blue = pixels[index + 2];
        const distance = Math.abs(red - background.red)
          + Math.abs(green - background.green)
          + Math.abs(blue - background.blue);
        const darkness = 255 - Math.max(red, green, blue);
        const saturation = Math.max(red, green, blue) - Math.min(red, green, blue);
        if (distance > 52 || darkness > 54 || saturation > 42) {
          foreground[y * width + x] = 1;
        }
      }
    }

    const component = bestForegroundComponent(foreground, width, height);
    if (!component) return sourceCanvas;

    const padding = Math.max(4, Math.round(Math.max(component.width, component.height) * 0.12));
    const cropLeft = Math.max(0, component.minX - padding);
    const cropTop = Math.max(0, component.minY - padding);
    const cropRight = Math.min(width, component.maxX + padding + 1);
    const cropBottom = Math.min(height, component.maxY + padding + 1);
    const cropWidth = cropRight - cropLeft;
    const cropHeight = cropBottom - cropTop;

    if (cropWidth < 12 || cropHeight < 18 || cropWidth * cropHeight > width * height * 0.82) {
      return sourceCanvas;
    }

    const outputSize = Math.max(48, Math.min(140, Math.max(cropWidth, cropHeight) + 8));
    const outputCanvas = document.createElement('canvas');
    outputCanvas.width = outputSize;
    outputCanvas.height = outputSize;
    const outputContext = outputCanvas.getContext('2d');
    outputContext.fillStyle = '#ffffff';
    outputContext.fillRect(0, 0, outputSize, outputSize);
    const dx = Math.round((outputSize - cropWidth) / 2);
    const dy = Math.round((outputSize - cropHeight) / 2);
    outputContext.drawImage(sourceCanvas, cropLeft, cropTop, cropWidth, cropHeight, dx, dy, cropWidth, cropHeight);
    return outputCanvas;
  }

  function averageCornerColor(pixels, width, height) {
    const samples = [];
    const sampleSize = Math.min(12, Math.floor(Math.min(width, height) / 4));
    const regions = [
      [0, 0],
      [Math.max(0, width - sampleSize), 0],
      [0, Math.max(0, height - sampleSize)],
      [Math.max(0, width - sampleSize), Math.max(0, height - sampleSize)],
    ];
    regions.forEach(([startX, startY]) => {
      for (let y = startY; y < startY + sampleSize && y < height; y += 1) {
        for (let x = startX; x < startX + sampleSize && x < width; x += 1) {
          const index = (y * width + x) * 4;
          if (pixels[index + 3] < 24) continue;
          samples.push([pixels[index], pixels[index + 1], pixels[index + 2]]);
        }
      }
    });

    if (!samples.length) return { red: 255, green: 255, blue: 255 };
    const totals = samples.reduce((sum, color) => {
      sum.red += color[0];
      sum.green += color[1];
      sum.blue += color[2];
      return sum;
    }, { red: 0, green: 0, blue: 0 });
    return {
      red: totals.red / samples.length,
      green: totals.green / samples.length,
      blue: totals.blue / samples.length,
    };
  }

  function bestForegroundComponent(foreground, width, height) {
    const visited = new Uint8Array(width * height);
    let best = null;

    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const start = y * width + x;
        if (!foreground[start] || visited[start]) continue;

        const stack = [start];
        visited[start] = 1;
        let pixels = 0;
        let minX = x;
        let maxX = x;
        let minY = y;
        let maxY = y;

        while (stack.length) {
          const current = stack.pop();
          const currentX = current % width;
          const currentY = Math.floor(current / width);
          pixels += 1;
          if (currentX < minX) minX = currentX;
          if (currentX > maxX) maxX = currentX;
          if (currentY < minY) minY = currentY;
          if (currentY > maxY) maxY = currentY;

          const neighbors = [current - 1, current + 1, current - width, current + width];
          for (const next of neighbors) {
            if (next < 0 || next >= foreground.length || visited[next] || !foreground[next]) continue;
            const nextX = next % width;
            if (Math.abs(nextX - currentX) > 1) continue;
            visited[next] = 1;
            stack.push(next);
          }
        }

        const componentWidth = maxX - minX + 1;
        const componentHeight = maxY - minY + 1;
        if (pixels < 24 || componentWidth < 5 || componentHeight < 12) continue;

        const aspect = componentWidth / Math.max(1, componentHeight);
        const productLike = componentHeight >= 18 && aspect <= 1.8;
        if (!productLike) continue;

        const centerX = (minX + maxX) / 2;
        const score = pixels + componentHeight * 9 + componentWidth * 3 + Math.max(0, centerX - width * 0.22) * 0.8;
        if (!best || score > best.score) {
          best = { minX, maxX, minY, maxY, width: componentWidth, height: componentHeight, pixels, score };
        }
      }
    }

    return best;
  }

  function loadImage(dataUrl) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error('No se pudo leer captura para recortar imagen.'));
      image.src = dataUrl;
    });
  }

  async function extractInvoiceFromScreenshots(apiKey, screenshots, domOrder) {
    const prompt = [
      'You are extracting an AliExpress order page into purchase-invoice JSON for OCR import.',
      `You will receive ${screenshots.length} sequential screenshot(s) covering the page top-to-bottom; they may overlap slightly. Merge them and DEDUPE rows that appear in two consecutive shots.`,
      'Return ONLY valid JSON. No markdown. No comments.',
      'Ignore page chrome, menus, support/help widgets, recommendations, "More to love", "You may also like", and anything that is not an actual purchased order line.',
      'Extract every distinct purchased order item visible across the screenshots.',
      'For each row, return the FULL product title even if a "Brand+" badge, color swatch, or other UI element visually overlaps part of the text. Do not return abbreviated titles.',
      'Keep separate rows for different colors/variants even when title, product ID, unit price, and quantity match.',
      'Parse Chilean peso-style prices such as "$3.441" as 3441 (no decimals).',
      'Use CLP for currency.',
      'If a field is not visible, use null or an empty string. Do not guess shipping from recommendations.',
      'JSON shape:',
      '{"orderNumber":"","orderDate":"YYYY-MM-DD or empty","subtotal":number|null,"shipping":number|null,"total":number|null,"items":[{"description":"","variant":"","quantity":number,"unitPrice":number,"total":number,"currency":"CLP"}]}',
      domOrder ? `Known DOM hints (may be incomplete, the screenshots are authoritative): ${JSON.stringify(buildAiDomHints(domOrder)).slice(0, 2400)}` : '',
    ].filter(Boolean).join('\n');

    const parts = [{ text: prompt }];
    screenshots.forEach((shot, index) => {
      parts.push({ text: `Screenshot ${index + 1} of ${screenshots.length} (scrollY=${shot.y}px):` });
      parts.push({ inline_data: { mime_type: 'image/png', data: shot.base64 } });
    });

    const { payload } = await callGeminiGenerateContent(apiKey, {
      contents: [{ role: 'user', parts }],
      generationConfig: {
        temperature: 0.1,
        response_mime_type: 'application/json',
      },
    });

    const text = payload?.candidates?.[0]?.content?.parts?.map((part) => part.text || '').join('\n') || '';
    return parseAiJson(text);
  }

  async function callGeminiGenerateContent(apiKey, body) {
    let lastMessage = 'Gemini API request failed.';

    for (const model of GEMINI_MODELS) {
      const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      const payload = await response.json().catch(() => null);
      if (response.ok) {
        return { model, payload };
      }

      const message = payload && payload.error && payload.error.message
        ? payload.error.message
        : `Gemini API error ${response.status}`;

      // Move on when the model alias is deprecated/unavailable for this account.
      if (response.status === 404 || /no longer available|not found|deprecated|not supported/i.test(message)) {
        lastMessage = message;
        continue;
      }

      throw new Error(message);
    }

    throw new Error(lastMessage);
  }

  function buildAiDomHints(order) {
    return {
      orderNumber: order.orderNumber || '',
      orderDate: order.orderDate || '',
      subtotal: order.subtotal || null,
      shipping: order.shipping || null,
      total: order.total || null,
      items: (order.items || []).slice(0, 30).map((item) => ({
        description: item.description || '',
        quantity: item.quantity || null,
        unitPrice: item.unitPrice || null,
        total: item.total || null,
        hasImage: Boolean(item.imageUrl),
        itemId: item.itemId || '',
      })),
    };
  }

  function parseAiJson(text) {
    const trimmed = String(text || '').trim();
    if (!trimmed) throw new Error('Gemini no devolvio texto.');

    try {
      return JSON.parse(trimmed);
    } catch (_error) {
      const match = trimmed.match(/\{[\s\S]*\}/);
      if (!match) throw new Error('Gemini no devolvio JSON parseable.');
      return JSON.parse(match[0]);
    }
  }

  function findBestDomMatch(aiDescription, aiItem, domItems, usedSet) {
    if (!domItems.length) return -1;
    const aiTokens = tokenize(aiDescription);
    const aiQty = toNumber(aiItem && aiItem.quantity) || 0;
    const aiPrice = toNumber(aiItem && aiItem.unitPrice) || 0;

    let bestIdx = -1;
    let bestScore = 0;
    for (let i = 0; i < domItems.length; i++) {
      if (usedSet.has(i)) continue;
      const dom = domItems[i] || {};
      const domTokens = tokenize(dom.description || '');
      const overlap = jaccard(aiTokens, domTokens);
      let score = overlap; // 0..1

      // Boost when quantity matches and unit price is close.
      if (aiQty && Number(dom.quantity) === aiQty) score += 0.15;
      if (aiPrice && dom.unitPrice) {
        const ratio = Math.min(aiPrice, dom.unitPrice) / Math.max(aiPrice, dom.unitPrice);
        if (ratio >= 0.95) score += 0.15;
      }

      if (score > bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }

    // Require some real textual overlap before accepting.
    return bestScore >= 0.15 ? bestIdx : -1;
  }

  function tokenize(text) {
    return new Set(
      String(text || '')
        .toLowerCase()
        .replace(/[^\p{L}\p{N}\s]/gu, ' ')
        .split(/\s+/)
        .filter((token) => token.length >= 3)
    );
  }

  function jaccard(a, b) {
    if (!a.size || !b.size) return 0;
    let inter = 0;
    a.forEach((token) => { if (b.has(token)) inter++; });
    const union = a.size + b.size - inter;
    return union === 0 ? 0 : inter / union;
  }

  function applyAiOrder(aiOrder, domOrder) {
    const domItems = (domOrder && domOrder.items ? domOrder.items : []).map(normalizeItem);
    const domMedia = Array.isArray(domOrder && domOrder.media)
      ? domOrder.media.map(normalizeMediaItem)
      : [];
    const aiItems = Array.isArray(aiOrder && aiOrder.items) ? aiOrder.items : [];
    if (aiItems.length === 0) throw new Error('AI OCR no encontro lineas de productos visibles.');

    const usedDom = new Set();
    const usedMedia = new Set();
    const items = aiItems.map((item, index) => {
      const aiDescription = [item.description, item.variant]
        .map((value) => String(value || '').trim())
        .filter(Boolean)
        .join(' - ');
      let matchIdx = findBestDomMatch(aiDescription, item, domItems, usedDom);
      // Positional fallback: if fuzzy match failed but we have a DOM item at the
      // same visual order position, trust it. AliExpress renders rows top-to-bottom
      // and Gemini reads them the same way, so index alignment is usually correct.
      if (matchIdx < 0 && domItems[index] && !usedDom.has(index)) {
        matchIdx = index;
      }
      const rawDomItem = matchIdx >= 0 ? domItems[matchIdx] : {};
      if (matchIdx >= 0) usedDom.add(matchIdx);

      const domItem = hasUsableDomIdentity(rawDomItem) ? rawDomItem : {};
      const mediaItem = pickBestMediaForItem(index, matchIdx, domItem, domMedia, usedMedia, aiDescription);

      const quantity = toNumber(item.quantity) || 1;
      const unitPrice = toNumber(item.unitPrice);
      const total = toNumber(item.total) || roundMoney(quantity * unitPrice);
      const description = aiDescription || domItem.description || mediaItem.title || `AliExpress item ${index + 1}`;

      return normalizeItem({
        sku: domItem.sku || mediaItem.sku || `AE-${String(index + 1).padStart(3, '0')}`,
        description,
        quantity,
        unitPrice,
        total,
        productUrl: domItem.productUrl || mediaItem.productUrl || '',
        itemId: domItem.itemId || mediaItem.itemId || '',
        imageUrl: domItem.imageUrl || mediaItem.imageUrl || '',
      });
    });

    state.items = items;
    state.pageUrl = domOrder?.pageUrl || state.pageUrl;
    state.pageTitle = domOrder?.pageTitle || state.pageTitle;
    state.extractedAt = new Date().toISOString();
    state.warnings = ['Lineas extraidas con AI Vision OCR; revisar antes de generar PDF.'];

    if (domOrder) {
      if (!el.supplierName.value.trim()) el.supplierName.value = domOrder.supplierName || 'AliExpress Marketplace';
      if (!el.supplierTaxId.value.trim()) el.supplierTaxId.value = domOrder.supplierTaxId || '';
      if (!el.orderNumber.value.trim()) el.orderNumber.value = domOrder.orderNumber || '';
      if (!el.orderDate.value) el.orderDate.value = domOrder.orderDate || new Date().toISOString().slice(0, 10);
      if (!el.notes.value.trim()) el.notes.value = domOrder.notes || '';
    }

    if (aiOrder.orderNumber) el.orderNumber.value = String(aiOrder.orderNumber);
    if (aiOrder.orderDate && /^\d{4}-\d{2}-\d{2}$/.test(String(aiOrder.orderDate))) el.orderDate.value = aiOrder.orderDate;
    el.currency.value = 'CLP';

    const itemSum = sumItems(items);
    const subtotal = toNullableNumber(aiOrder.subtotal) ?? toNullableNumber(domOrder?.subtotal) ?? itemSum;
    let shipping = toNullableNumber(aiOrder.shipping) ?? toNullableNumber(domOrder?.shipping);
    const total = toNullableNumber(aiOrder.total) ?? toNullableNumber(domOrder?.total) ?? roundMoney(itemSum + (shipping || 0));
    const derivedShipping = roundMoney((total || 0) - (subtotal || 0));
    if (derivedShipping >= 0 && (shipping === null || Math.abs(roundMoney((subtotal || 0) + shipping) - total) > 0.01)) {
      shipping = derivedShipping;
    }
    state.subtotal = subtotal;
    state.shipping = shipping;
    state.tax = domOrder?.tax || state.tax;
    state.discount = domOrder?.discount || state.discount;

    el.subtotal.value = numberForInput(subtotal);
    el.shipping.value = numberForInput(shipping);
    el.total.value = numberForInput(total);

    renderItems();
  }

  function applyOrder(order) {
    state.pageUrl = order.pageUrl || '';
    state.pageTitle = order.pageTitle || '';
    state.extractedAt = order.extractedAt || new Date().toISOString();
    state.warnings = order.warnings || [];
    state.subtotal = toNullableNumber(order.subtotal);
    state.shipping = toNullableNumber(order.shipping);
    state.tax = toNullableNumber(order.tax);
    state.discount = toNullableNumber(order.discount);
    state.items = (order.items || []).map(normalizeItem);

    el.supplierName.value = order.supplierName || 'AliExpress Marketplace';
    el.supplierTaxId.value = order.supplierTaxId || '';
    el.orderNumber.value = order.orderNumber || '';
    el.orderDate.value = order.orderDate || new Date().toISOString().slice(0, 10);
    el.currency.value = 'CLP';
    el.total.value = numberForInput(order.total || sumItems(state.items));
    el.subtotal.value = numberForInput(state.subtotal || sumItems(state.items));
    el.shipping.value = numberForInput(state.shipping);
    el.notes.value = order.notes || '';

    renderItems();
  }

  function renderItems() {
    if (state.items.length === 0) {
      el.itemsList.innerHTML = '<p class="status neutral">Sin productos todavia. Puedes agregarlos manualmente.</p>';
      return;
    }

    el.itemsList.innerHTML = state.items.map((item, index) => `
      <article class="item-row" data-index="${index}">
        <div class="item-row-header">
          <span class="item-row-title">
            ${item.imageUrl ? `<img class="item-thumb" src="${escapeAttr(item.imageUrl)}" alt="">` : ''}
            Linea ${index + 1}
          </span>
          <button type="button" class="remove-item-button" data-remove-index="${index}">Quitar</button>
        </div>
        <div class="item-grid">
          <label>SKU<input data-field="sku" type="text" value="${escapeAttr(item.sku)}"></label>
          <label>Descripcion<input data-field="description" type="text" value="${escapeAttr(item.description)}"></label>
          <label>Cant.<input data-field="quantity" type="number" step="0.01" min="0" value="${numberForInput(item.quantity)}"></label>
          <label>Precio<input data-field="unitPrice" type="number" step="0.01" min="0" value="${numberForInput(item.unitPrice)}"></label>
          <label>Total<input data-field="total" type="number" step="0.01" min="0" value="${numberForInput(item.total)}"></label>
        </div>
      </article>
    `).join('');
  }

  function renderDebug(debug) {
    let debugElement = document.getElementById('debugPanel');
    if (!debug) {
      if (debugElement) debugElement.remove();
      return;
    }

    if (!debugElement) {
      debugElement = document.createElement('section');
      debugElement.id = 'debugPanel';
      debugElement.className = 'panel debug-panel';
      el.status.insertAdjacentElement('afterend', debugElement);
    }

    debugElement.innerHTML = `
      <div class="section-heading">
        <h2>Debug imagenes</h2>
        <button id="copyDebugButton" type="button" class="secondary-button">Copiar debug</button>
      </div>
      <pre>${escapeHtml(JSON.stringify(debug, null, 2))}</pre>
    `;
    const button = debugElement.querySelector('#copyDebugButton');
    if (button) {
      button.addEventListener('click', async () => {
        await navigator.clipboard.writeText(JSON.stringify(debug, null, 2));
        setStatus('Debug copiado al portapapeles.', 'neutral');
      });
    }
  }

  function toDebugItem(item) {
    return {
      ...item,
      imageUrl: summarizeDebugImageUrl(item.imageUrl),
    };
  }

  function summarizeDebugImageUrl(imageUrl) {
    const value = String(imageUrl || '');
    if (!value.startsWith('data:')) return value;
    const header = value.slice(0, Math.min(value.indexOf(',') + 1 || 32, 32));
    return `${header}... (${value.length} chars)`;
  }

  async function generateInvoice() {
    const invoice = collectInvoice();
    const validationError = validateInvoice(invoice);
    if (validationError) {
      setStatus(validationError, 'error');
      return;
    }

    const draftId = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    await chrome.storage.local.set({ [`${STORAGE_PREFIX}${draftId}`]: invoice });
    await chrome.tabs.create({ url: chrome.runtime.getURL(`invoice.html?draft=${encodeURIComponent(draftId)}`) });
  }

  function collectInvoice() {
    return {
      source: 'AliExpress',
      generatedAt: new Date().toISOString(),
      extractedAt: state.extractedAt || '',
      pageUrl: state.pageUrl,
      pageTitle: state.pageTitle,
      supplierName: el.supplierName.value.trim() || 'AliExpress Marketplace',
      supplierTaxId: el.supplierTaxId.value.trim(),
      orderNumber: el.orderNumber.value.trim(),
      orderDate: el.orderDate.value || new Date().toISOString().slice(0, 10),
      currency: 'CLP',
      subtotal: toNullableNumber(el.subtotal.value),
      shipping: toNullableNumber(el.shipping.value),
      tax: state.tax,
      discount: state.discount,
      total: toNumber(el.total.value),
      notes: el.notes.value.trim(),
      items: state.items.map(normalizeItem).filter((item) => item.description || item.sku),
      warnings: state.warnings,
    };
  }

  function validateInvoice(invoice) {
    if (!invoice.orderNumber) return 'Falta el numero de pedido/factura.';
    if (!invoice.orderDate) return 'Falta la fecha.';
    if (!invoice.items.length) return 'Agrega al menos una linea de producto.';
    if (!invoice.total || invoice.total <= 0) return 'El total debe ser mayor a cero.';
    return '';
  }

  function downloadJson() {
    const invoice = collectInvoice();
    downloadBlob(
      JSON.stringify(invoice, null, 2),
      `aliexpress-invoice-${safeFilePart(invoice.orderNumber || Date.now())}.json`,
      'application/json',
    );
  }

  async function copyOcrText() {
    try {
      const invoice = collectInvoice();
      await navigator.clipboard.writeText(buildOcrText(invoice));
      setStatus('Texto OCR copiado al portapapeles.', 'success');
    } catch (error) {
      setStatus(error.message || String(error), 'error');
    }
  }

  function buildOcrText(invoice) {
    const date = formatDateForOcr(invoice.orderDate);
    const lines = [
      'FACTURA DE COMPRA',
      invoice.supplierName,
    ];
    if (invoice.supplierTaxId) lines.push(`RUT: ${invoice.supplierTaxId}`);
    lines.push(`Pedido # ${invoice.orderNumber}`);
    lines.push(`Fecha: ${date}`);
    lines.push('SKU DESCRIPCION CANTIDAD PRECIO IMPORTE');
    lines.push('IMPORTE');

    invoice.items.forEach((item) => {
      lines.push(`[${item.sku || 'AE-ITEM'}] ${item.description}`);
      if (item.productUrl) lines.push(item.productUrl);
      lines.push(formatDecimalComma(item.quantity || 1));
      lines.push('Unidades');
      lines.push(formatDecimalComma(item.unitPrice || 0));
      lines.push('$');
      lines.push(formatDecimalComma(item.total || 0));
    });

    lines.push(`Total neto $ ${formatDecimalComma(invoice.subtotal || sumItems(invoice.items))}`);
    if (invoice.shipping) lines.push(`Envio $ ${formatDecimalComma(invoice.shipping)}`);
    lines.push(`TOTAL $ ${formatDecimalComma(invoice.total)}`);
    if (invoice.notes) lines.push(invoice.notes);
    return lines.join('\n');
  }

  function createEmptyItem() {
    return {
      sku: `AE-${String(state.items.length + 1).padStart(3, '0')}`,
      description: '',
      quantity: 1,
      unitPrice: 0,
      total: 0,
      productUrl: '',
      itemId: '',
      imageUrl: '',
    };
  }

  function normalizeMediaItem(item) {
    const itemId = String(item.itemId || '').trim();
    const title = String(item.title || '').trim();
    return {
      sku: String(item.sku || (itemId ? `AE-${itemId.slice(-8)}` : '')).trim(),
      productUrl: item.productUrl || '',
      itemId,
      imageUrl: item.imageUrl || '',
      title,
      variantKey: variantIdentityKeyFromText(title),
    };
  }

  function mergeMediaRows(primaryRows, secondaryRows) {
    const merged = [];
    const seen = new Set();

    [...primaryRows, ...secondaryRows].forEach((item) => {
      const media = normalizeMediaItem(item);
      if (!media.imageUrl && !media.productUrl && !media.itemId) return;
      const imageKey = imageIdentityKey(media.imageUrl);
      const productKey = media.itemId || normalizeProductUrl(media.productUrl) || '';
      const key = [productKey || imageKey, media.variantKey || imageKey].filter(Boolean).join('|');
      if (!key || seen.has(key)) return;
      seen.add(key);
      merged.push(media);
    });

    return merged;
  }

  function hasUsableDomIdentity(item) {
    if (!item) return false;
    if (item.itemId || item.imageUrl) return true;
    return /\/item\/|itemId=|productId=/i.test(String(item.productUrl || ''));
  }

  function pickBestMediaForItem(index, matchIdx, domItem, domMedia, usedMedia, aiDescription = '') {
    if (!domMedia.length) return {};

    const targetVariantKey = variantIdentityKeyFromText([
      aiDescription,
      domItem && domItem.description,
      domItem && domItem.title,
    ].filter(Boolean).join(' '));

    if (targetVariantKey) {
      const variantIndex = domMedia.findIndex((media, mediaIndex) =>
        !usedMedia.has(mediaIndex) && media.variantKey === targetVariantKey
      );
      if (variantIndex >= 0) {
        usedMedia.add(variantIndex);
        return domMedia[variantIndex];
      }
    }

    const preferredIndexes = [];
    if (hasUsableDomIdentity(domItem) && Number.isInteger(matchIdx) && matchIdx >= 0) {
      preferredIndexes.push(matchIdx);
    }
    if (Number.isInteger(index) && index >= 0) preferredIndexes.push(index);

    for (const candidateIndex of preferredIndexes) {
      if (!domMedia[candidateIndex]) continue;
      if (!usedMedia.has(candidateIndex)) usedMedia.add(candidateIndex);
      return domMedia[candidateIndex];
    }

    const unusedIndex = domMedia.findIndex((media, mediaIndex) => !usedMedia.has(mediaIndex) && (media.imageUrl || media.productUrl || media.itemId));
    if (unusedIndex >= 0) {
      usedMedia.add(unusedIndex);
      return domMedia[unusedIndex];
    }

    return domMedia[Math.min(index, domMedia.length - 1)] || domMedia[0] || {};
  }

  function normalizeItem(item) {
    const quantity = toNumber(item.quantity) || 1;
    const unitPrice = toNumber(item.unitPrice);
    const total = toNumber(item.total) || roundMoney(quantity * unitPrice);
    return {
      sku: String(item.sku || '').trim(),
      description: String(item.description || '').trim(),
      quantity,
      unitPrice,
      total,
      productUrl: item.productUrl || '',
      itemId: item.itemId || '',
      imageUrl: item.imageUrl || '',
    };
  }

  function variantIdentityKeyFromText(value) {
    return [
      extractVariantCodesFromText(value).join('|'),
      variantLabelKeyFromText(value),
    ].filter(Boolean).join('|');
  }

  function extractVariantCodesFromText(value) {
    return Array.from(new Set((String(value || '').match(/\b\d{8,14}\b/g) || [])
      .filter((code) => !/^100\d{10,18}$/.test(code))));
  }

  function variantLabelKeyFromText(value) {
    const text = String(value || '').toLowerCase();
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
    return normalizeAliExpressImageUrl(imageUrl).replace(/[?#].*$/, '').replace(/_[0-9]+x[0-9]+\.(jpg|jpeg|png|webp)$/i, '.$1');
  }

  function normalizeProductUrl(url) {
    try {
      const parsed = new URL(String(url || ''), 'https://www.aliexpress.com');
      const itemId = parsed.pathname.match(/\/item\/(\d+)\.html/i)?.[1]
        || parsed.searchParams.get('itemId')
        || parsed.searchParams.get('productId')
        || '';
      return itemId || parsed.pathname;
    } catch (_error) {
      return String(url || '').split(/[?#]/)[0];
    }
  }

  function hydrateMissingOrderCropImages(screenshots) {
    const crops = (screenshots || [])
      .flatMap((shot) => Array.isArray(shot.imageCrops) ? shot.imageCrops : [])
      .filter((crop) => crop && crop.dataUrl)
      .sort((a, b) => (a.pageY || 0) - (b.pageY || 0) || (a.pageX || 0) - (b.pageX || 0));

    const debug = {
      cropCount: crops.length,
      crops: crops.slice(0, 12).map((crop) => ({
        pageY: crop.pageY,
        pageX: crop.pageX,
        variantCodes: crop.variantCodes || [],
        itemId: crop.itemId || '',
        imageUrl: crop.imageUrl || '',
        productUrl: crop.productUrl || '',
        source: crop.source || '',
        width: crop.width,
        height: crop.height,
        rowText: crop.rowText || '',
      })),
      assignments: [],
      skippedCrops: [],
    };

    if (crops.length === 0) return debug;

    const usedCrops = new Set();
    state.items.forEach((item, index) => {
      if (item.imageUrl) return;
      const codes = extractVariantCodesFromItem(item);
      let cropIndex = selectBestOrderCropIndex(crops, usedCrops, codes, index);

      if (cropIndex < 0 && crops[index] && !usedCrops.has(index)) cropIndex = index;
      if (cropIndex < 0) {
        cropIndex = crops.findIndex((_crop, candidateIndex) => !usedCrops.has(candidateIndex));
      }
      if (cropIndex < 0 || !crops[cropIndex]) return;

      const imageUrl = normalizeAliExpressImageUrl(crops[cropIndex].imageUrl || '');
      if (!imageUrl) {
        debug.skippedCrops.push({
          index,
          cropIndex,
          codes,
          cropCodes: crops[cropIndex].variantCodes || [],
          source: crops[cropIndex].source || '',
          reason: 'screenshot-crop-data-url-disabled',
        });
        return;
      }

      usedCrops.add(cropIndex);
      item.imageUrl = imageUrl;
      debug.assignments.push({
        index,
        cropIndex,
        codes,
        cropCodes: crops[cropIndex].variantCodes || [],
        source: 'order-page-image-url',
        imageUrl,
        usedScreenshotDataUrl: false,
        replacedExistingImage: false,
      });
    });

    if (debug.assignments.length > 0) renderItems();
    return debug;
  }

  function selectBestOrderCropIndex(crops, usedCrops, codes, itemIndex) {
    if (!codes.length) return -1;

    const candidates = crops
      .map((crop, cropIndex) => ({ crop, cropIndex }))
      .filter(({ crop, cropIndex }) => {
        if (usedCrops.has(cropIndex)) return false;
        const cropCodes = crop.variantCodes || [];
        return codes.some((code) => cropCodes.includes(code));
      })
      .map(({ crop, cropIndex }) => {
        const cropCodes = crop.variantCodes || [];
        const exactSingleCode = cropCodes.length === 1 && codes.includes(cropCodes[0]);
        const mixedCodePenalty = cropCodes.length > 1 ? 100000 : 0;
        const indexPenalty = Math.abs(cropIndex - itemIndex) * 20;
        const sourcePenalty = crop.source === 'visual-row-approximation' ? 10 : 0;
        return {
          cropIndex,
          score: (exactSingleCode ? 1000000 : 0) - mixedCodePenalty - indexPenalty - sourcePenalty,
        };
      })
      .sort((a, b) => b.score - a.score || a.cropIndex - b.cropIndex);

    return candidates[0] ? candidates[0].cropIndex : -1;
  }

  async function hydrateMissingProductImages(domOrder) {
    const debug = {
      inheritedIdentity: [],
      fetchedProducts: [],
      assignments: [],
      errors: [],
    };

    inheritMissingProductIdentity(domOrder, debug);
    const missingIndexes = state.items
      .map((item, index) => ({ item, index }))
      .filter(({ item }) => !item.imageUrl && productPageUrlForItem(item));

    if (missingIndexes.length === 0) return debug;

    const groups = new Map();
    missingIndexes.forEach(({ item, index }) => {
      const productUrl = productPageUrlForItem(item);
      if (!productUrl) return;
      if (!groups.has(productUrl)) groups.set(productUrl, []);
      groups.get(productUrl).push(index);
    });

    for (const [productUrl, indexes] of groups.entries()) {
      try {
        setStatus(`Buscando imagenes de producto en AliExpress (${debug.fetchedProducts.length + 1}/${groups.size})...`, 'neutral');
        const groupVariantCodes = Array.from(new Set(
          indexes.flatMap((index) => extractVariantCodesFromItem(state.items[index]))
        ));
        const productInfo = await sanitizeProductInfoImages(
          await fetchAliExpressProductImages(productUrl, groupVariantCodes.length > 0)
        );
        debug.fetchedProducts.push({
          productUrl,
          requestedVariantCodes: groupVariantCodes,
          strategy: productInfo.strategy || '',
          imageCount: productInfo.images.length,
          primaryImage: productInfo.primaryImage || '',
          variantImageCount: Object.keys(productInfo.variantImages || {}).length,
          variantImages: productInfo.variantImages || {},
          swatchImages: productInfo.swatchImages || [],
        });

        indexes.forEach((index) => {
          const item = state.items[index];
          const codes = extractVariantCodesFromItem(item);
          const variantImage = findVariantImage(productInfo, codes);
          const imageUrl = variantImage || productInfo.primaryImage || productInfo.images[0] || '';
          if (!imageUrl) return;
          item.imageUrl = imageUrl;
          debug.assignments.push({
            index,
            codes,
            source: variantImage ? 'variant-near-code' : 'product-primary',
            imageUrl,
          });
        });
      } catch (error) {
        debug.errors.push({
          productUrl,
          error: error && error.message ? error.message : String(error),
        });
      }
    }

    if (debug.assignments.length > 0) renderItems();
    return debug;
  }

  function inheritMissingProductIdentity(domOrder, debug) {
    const sources = [
      ...(Array.isArray(domOrder && domOrder.items) ? domOrder.items : []),
      ...state.items,
    ]
      .map(normalizeItem)
      .filter((item) => item.productUrl || item.itemId);

    state.items.forEach((item, index) => {
      if (item.productUrl || item.itemId || sources.length === 0) return;
      const match = findBestIdentitySource(item, sources);
      if (!match) return;
      item.productUrl = match.productUrl || productPageUrlForItem(match);
      item.itemId = match.itemId || extractAliExpressItemId(match.productUrl);
      if (!item.sku && item.itemId) item.sku = `AE-${String(item.itemId).slice(-8)}`;
      debug.inheritedIdentity.push({
        index,
        itemId: item.itemId,
        productUrl: item.productUrl,
        sourceDescription: match.description,
      });
    });
  }

  function findBestIdentitySource(item, sources) {
    const itemTokens = tokenize(item.description || '');
    const itemPrice = toNumber(item.unitPrice);
    let best = null;
    let bestScore = 0;

    sources.forEach((source) => {
      const score = jaccard(itemTokens, tokenize(source.description || ''))
        + (itemPrice && source.unitPrice && Math.abs(itemPrice - source.unitPrice) < 0.01 ? 0.2 : 0);
      if (score > bestScore) {
        best = source;
        bestScore = score;
      }
    });

    return bestScore >= 0.35 ? best : null;
  }

  function productPageUrlForItem(item) {
    const itemId = item.itemId || extractAliExpressItemId(item.productUrl);
    if (itemId) return `https://www.aliexpress.com/item/${encodeURIComponent(itemId)}.html`;
    const url = String(item.productUrl || '').trim();
    if (/^https:\/\/([^/]+\.)?aliexpress\.com\/item\//i.test(url)) return url;
    return '';
  }

  async function fetchAliExpressProductImages(productUrl, preferRenderedVariantMap) {
    try {
      if (preferRenderedVariantMap) throw new Error('Rendered variant map requested.');
      const response = await fetch(productUrl, {
        credentials: 'include',
        cache: 'no-store',
      });
      if (!response.ok) throw new Error(`AliExpress producto HTTP ${response.status}`);
      const html = decodeAliExpressHtml(await response.text());
      const images = extractAliExpressImageUrls(html);
      const primaryImage = extractPrimaryAliExpressImage(html, images);
      const variantImages = extractVariantImageMapFromHtml(html);
      if (images.length || primaryImage) return { strategy: 'fetch-html', html, images, primaryImage, variantImages, swatchImages: [] };
    } catch (_error) {
      // AliExpress can redirect-loop direct extension fetches; rendered-tab fallback uses the user's logged-in browser context.
    }

    return fetchAliExpressProductImagesViaRenderedTab(productUrl);
  }

  async function fetchAliExpressProductImagesViaRenderedTab(productUrl) {
    const tab = await chrome.tabs.create({ url: productUrl, active: false });
    try {
      await waitForTabComplete(tab.id, 15000);
      await sleep(1600);
      const results = await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: async () => {
          const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

          function norm(url) {
            let value = String(url || '').trim();
            if (!value) return '';
            value = value.replace(/\\u002F/gi, '/').replace(/\\\//g, '/').replace(/&amp;/g, '&');
            if (value.startsWith('//')) value = `https:${value}`;
            value = value.replace(/^http:\/\//i, 'https://');
            return value.replace(/\.(jpg|jpeg|png|webp)_[^/?#]+/i, '.$1');
          }
          function ok(url) {
            return /alicdn\.com\/(?:kf|imgextra|bao\/uploaded)/i.test(url)
              && !/sprite|logo|avatar|qr|barcode|icon|loading|transparent|placeholder|feedback|coupon/i.test(url);
          }

          function isPlaceholderImageUrl(url) {
            return /^data:image\/(?:gif|svg\+xml)/i.test(url)
              || /(?:transparent|placeholder|loading|spinner|blank|pixel|1x1|grey\.gif|empty)/i.test(url);
          }

          const urls = [];
          const seen = new Set();
          function add(url) {
            const normalized = norm(url);
            if (!normalized || seen.has(normalized) || !ok(normalized)) return;
            seen.add(normalized);
            urls.push(normalized);
          }

          function imageUrlFromElement(image) {
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
              ...srcsetCandidates,
              image.currentSrc,
              image.src,
            ].map(norm).filter(Boolean);
            return candidates.find((url) => !isPlaceholderImageUrl(url)) || candidates[0] || '';
          }

          function mainProductImageUrl() {
            const centerXLimit = Math.max(420, window.innerWidth * 0.45);
            const images = Array.from(document.querySelectorAll('img'))
              .map((image) => {
                const rect = image.getBoundingClientRect();
                const url = imageUrlFromElement(image);
                if (!url || !ok(url)) return null;
                if (rect.width < 150 || rect.height < 150) return null;
                if (rect.left > centerXLimit) return null;
                if (rect.top < 80 || rect.top > Math.max(680, window.innerHeight * 0.82)) return null;
                return {
                  url,
                  area: rect.width * rect.height,
                  left: rect.left,
                  top: rect.top,
                };
              })
              .filter(Boolean)
              .sort((a, b) => b.area - a.area || a.left - b.left || a.top - b.top);
            return images[0] ? images[0].url : '';
          }

          function selectedVariantCode() {
            const nodes = Array.from(document.querySelectorAll('span,div,p,strong,b'));
            for (let index = nodes.length - 1; index >= 0; index -= 1) {
              const node = nodes[index];
              const rect = node.getBoundingClientRect();
              if (rect.width <= 0 || rect.height <= 0) continue;
              const text = String(node.innerText || node.textContent || '').replace(/\s+/g, ' ').trim();
              if (text.length > 90) continue;
              const match = text.match(/\b(?:color|colour|cor)\s*[:：]\s*(\d{8,14})\b/i);
              if (match) return match[1];
            }

            const text = document.body ? (document.body.innerText || '') : '';
            const matches = Array.from(text.matchAll(/\b(?:color|colour|cor)\s*[:：]\s*(\d{8,14})\b/gi));
            return matches.length ? matches[matches.length - 1][1] : '';
          }

          function nearestClickable(element) {
            let current = element;
            for (let depth = 0; depth < 6 && current && current !== document.body; depth += 1) {
              const tag = current.tagName ? current.tagName.toLowerCase() : '';
              const role = current.getAttribute && current.getAttribute('role');
              const className = current.getAttribute && current.getAttribute('class') || '';
              if (tag === 'button' || tag === 'a' || role === 'button' || /sku|select|option|item|value/i.test(className)) return current;
              current = current.parentElement;
            }
            return element;
          }

          function hasColorOptionAncestor(element) {
            let current = element;
            for (let depth = 0; depth < 7 && current && current !== document.body; depth += 1) {
              const text = current.innerText || current.textContent || '';
              const className = current.getAttribute && current.getAttribute('class') || '';
              if (/\bcolor\s*[:：]/i.test(text) || /sku|sku-property|sku-item|product-property|option|variation/i.test(className)) return true;
              current = current.parentElement;
            }
            return false;
          }

          async function collectVariantImagesByClicking() {
            const variantImages = {};
            const swatchImages = [];
            const candidates = Array.from(document.querySelectorAll('img'))
              .map((image) => {
                const rect = image.getBoundingClientRect();
                const url = imageUrlFromElement(image);
                if (!url || !ok(url) || rect.width < 24 || rect.height < 24 || rect.width > 140 || rect.height > 140) return null;
                if (!hasColorOptionAncestor(image)) return null;
                return { image, rect, url, clickable: nearestClickable(image) };
              })
              .filter(Boolean)
              .sort((a, b) => a.rect.top - b.rect.top || a.rect.left - b.rect.left);

            for (const candidate of candidates.slice(0, 24)) {
              try {
                candidate.clickable.dispatchEvent(new MouseEvent('mouseover', { bubbles: true, cancelable: true, view: window }));
                candidate.clickable.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
                candidate.clickable.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
                candidate.clickable.click();
                await wait(650);
                const code = selectedVariantCode();
                const mainImage = mainProductImageUrl();
                if (code) {
                  const mappedImage = mainImage || candidate.url;
                  if (!swatchImages.includes(mappedImage)) swatchImages.push(mappedImage);
                  if (!variantImages[code]) variantImages[code] = mappedImage;
                }
              } catch (_error) {
                // Ignore individual swatch failures.
              }
            }
            return { variantImages, swatchImages };
          }

          document.querySelectorAll('meta[property="og:image"],meta[name="twitter:image"],link[rel="image_src"]').forEach((element) => {
            add(element.getAttribute('content') || element.getAttribute('href') || '');
          });
          document.querySelectorAll('img').forEach((image) => {
            add(imageUrlFromElement(image));
            String(image.getAttribute('srcset') || '').split(',').forEach((entry) => {
              add(entry.trim().split(/\s+/)[0] || '');
            });
          });
          document.querySelectorAll('[style*="background-image"]').forEach((element) => {
            const style = element.getAttribute('style') || '';
            const match = style.match(/url\(["']?([^"')]+)["']?\)/i);
            if (match) add(match[1]);
          });

          const html = document.documentElement ? document.documentElement.innerHTML : '';
          const pattern = /(?:https?:)?\/\/(?:ae01|ae02|ae03|ae04|ae05|ae-pic|img)\.alicdn\.com\/[A-Za-z0-9_./?=&%:+~-]+?\.(?:jpg|jpeg|png|webp)(?:_[A-Za-z0-9.]+)?/gi;
          let match;
          while ((match = pattern.exec(html)) !== null) add(match[0]);

          const variantResult = await collectVariantImagesByClicking();

          return {
            href: location.href,
            title: document.title || '',
            html,
            images: urls.slice(0, 100),
            variantImages: variantResult.variantImages || {},
            swatchImages: variantResult.swatchImages || [],
          };
        },
      });

      const result = results && results[0] ? (results[0].result || {}) : {};
      const html = decodeAliExpressHtml(result.html || '');
      const images = mergeImageUrlLists(result.images || [], extractAliExpressImageUrls(html));
      const primaryImage = images[0] || '';
      const variantImages = normalizeVariantImageMap({
        ...extractVariantImageMapFromHtml(html),
        ...(result.variantImages || {}),
      });
      const swatchImages = mergeImageUrlLists(result.swatchImages || [], []);
      return { strategy: 'rendered-tab', html, images, primaryImage, variantImages, swatchImages };
    } finally {
      if (tab && tab.id) {
        try { await chrome.tabs.remove(tab.id); } catch (_error) { /* ignore */ }
      }
    }
  }

  async function waitForTabComplete(tabId, timeoutMs) {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      const tab = await chrome.tabs.get(tabId);
      if (tab && tab.status === 'complete') return;
      await sleep(250);
    }
  }

  function mergeImageUrlLists(primary, secondary) {
    const urls = [];
    const seen = new Set();
    [...primary, ...secondary].forEach((url) => {
      const normalized = normalizeAliExpressImageUrl(url);
      if (!normalized || seen.has(normalized) || !looksLikeFinalProductPhotoUrl(normalized)) return;
      seen.add(normalized);
      urls.push(normalized);
    });
    return urls.sort((a, b) => productImageScore(b) - productImageScore(a)).slice(0, 100);
  }

  function decodeAliExpressHtml(value) {
    return String(value || '')
      .replace(/\\u002F/gi, '/')
      .replace(/\\\//g, '/')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#34;/g, '"')
      .replace(/&#39;/g, "'");
  }

  function extractPrimaryAliExpressImage(html, images) {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const meta = doc.querySelector('meta[property="og:image"],meta[name="twitter:image"],link[rel="image_src"]');
    const metaUrl = normalizeAliExpressImageUrl(meta ? (meta.getAttribute('content') || meta.getAttribute('href') || '') : '');
    if (metaUrl && looksLikeProductImageUrl(metaUrl)) return metaUrl;
    return images[0] || '';
  }

  function extractAliExpressImageUrls(html) {
    const urls = [];
    const seen = new Set();
    const pattern = /(?:https?:)?\/\/(?:ae01|ae02|ae03|ae04|ae05|ae-pic|img)\.alicdn\.com\/[A-Za-z0-9_./?=&%:+~-]+?\.(?:jpg|jpeg|png|webp)(?:_[A-Za-z0-9.]+)?/gi;
    let match;
    while ((match = pattern.exec(html)) !== null) {
      const url = normalizeAliExpressImageUrl(match[0]);
      if (!url || seen.has(url) || !looksLikeFinalProductPhotoUrl(url)) continue;
      seen.add(url);
      urls.push(url);
    }
    return urls.sort((a, b) => productImageScore(b) - productImageScore(a)).slice(0, 80);
  }

  function normalizeAliExpressImageUrl(url) {
    let value = String(url || '').trim();
    if (!value) return '';
    value = value.replace(/\\u002F/gi, '/').replace(/\\\//g, '/').replace(/&amp;/g, '&');
    if (value.startsWith('//')) value = `https:${value}`;
    value = value.replace(/^http:\/\//i, 'https://');
    value = value.replace(/\.(jpg|jpeg|png|webp)_[^/?#]+/i, '.$1');
    return value;
  }

  function looksLikeProductImageUrl(url) {
    const value = String(url || '');
    if (!/alicdn\.com\/(?:kf|imgextra|bao\/uploaded)/i.test(value)) return false;
    if (/sprite|logo|avatar|qr|barcode|icon|loading|transparent|placeholder|feedback|coupon/i.test(value)) return false;
    return true;
  }

  function looksLikeFinalProductPhotoUrl(url) {
    if (!looksLikeProductImageUrl(url)) return false;
    const dimensions = extractPathImageDimensions(url);
    if (!dimensions) return true;
    return dimensions.width >= 180 && dimensions.height >= 180;
  }

  async function sanitizeProductInfoImages(productInfo) {
    const images = await filterFinalProductPhotoUrls(productInfo.images || []);
    const primaryCandidates = await filterFinalProductPhotoUrls([
      productInfo.primaryImage || '',
      ...images,
    ]);

    const variantImages = {};
    for (const [code, imageUrl] of Object.entries(productInfo.variantImages || {})) {
      const normalized = normalizeAliExpressImageUrl(imageUrl);
      if (normalized && await isRemoteFinalProductPhotoUrl(normalized)) {
        variantImages[code] = normalized;
      }
    }

    const swatchImages = await filterFinalProductPhotoUrls(productInfo.swatchImages || []);
    return {
      ...productInfo,
      images,
      primaryImage: primaryCandidates[0] || images[0] || '',
      variantImages,
      swatchImages,
    };
  }

  async function filterFinalProductPhotoUrls(urls) {
    const seen = new Set();
    const result = [];
    for (const url of urls || []) {
      const normalized = normalizeAliExpressImageUrl(url);
      if (!normalized || seen.has(normalized)) continue;
      seen.add(normalized);
      if (await isRemoteFinalProductPhotoUrl(normalized)) result.push(normalized);
    }
    return result;
  }

  async function isRemoteFinalProductPhotoUrl(url) {
    const normalized = normalizeAliExpressImageUrl(url);
    if (!looksLikeFinalProductPhotoUrl(normalized)) return false;

    const dimensions = await measureRemoteImageDimensions(normalized);
    if (!dimensions) return true;
    const area = dimensions.width * dimensions.height;
    return dimensions.width >= 160 && dimensions.height >= 160 && area >= 30000;
  }

  function measureRemoteImageDimensions(url) {
    const normalized = normalizeAliExpressImageUrl(url);
    if (!normalized) return Promise.resolve(null);
    if (imageDimensionCache.has(normalized)) return imageDimensionCache.get(normalized);

    const promise = new Promise((resolve) => {
      const image = new Image();
      const timeout = setTimeout(() => resolve(null), 4500);
      image.onload = () => {
        clearTimeout(timeout);
        resolve({ width: image.naturalWidth || 0, height: image.naturalHeight || 0 });
      };
      image.onerror = () => {
        clearTimeout(timeout);
        resolve(null);
      };
      image.referrerPolicy = 'no-referrer';
      image.src = normalized;
    });

    imageDimensionCache.set(normalized, promise);
    return promise;
  }

  function extractPathImageDimensions(url) {
    const match = String(url || '').match(/\/(\d{1,4})x(\d{1,4})\.(?:jpg|jpeg|png|webp)(?:[?#]|$)/i);
    if (!match) return null;
    return {
      width: Number(match[1]) || 0,
      height: Number(match[2]) || 0,
    };
  }

  function productImageScore(url) {
    let score = 0;
    if (/\/kf\//i.test(url)) score += 80;
    if (/S[a-z0-9]{10,}/i.test(url)) score += 20;
    if (/_640x640|_720x720|_800x800|_960x960/i.test(url)) score += 14;
    if (/_50x50|_80x80|_100x100|_120x120/i.test(url)) score -= 25;
    if (/\.webp/i.test(url)) score += 2;
    return score;
  }

  function extractVariantCodesFromItem(item) {
    const itemId = String(item.itemId || extractAliExpressItemId(item.productUrl) || '');
    return Array.from(new Set(
      String(item.description || '')
        .match(/\b\d{8,14}\b/g) || []
    )).filter((code) => code !== itemId);
  }

  function extractVariantImageMapFromHtml(html) {
    const map = {};
    const text = decodeAliExpressHtml(html);
    const codePattern = /\b(\d{8,14})\b/g;
    let match;
    while ((match = codePattern.exec(text)) !== null) {
      const code = match[1];
      const chunk = text.slice(Math.max(0, match.index - 3000), Math.min(text.length, match.index + 3000));
      const image = extractAliExpressImageUrls(chunk)[0] || '';
      if (image && !map[code]) map[code] = image;
    }
    return normalizeVariantImageMap(map);
  }

  function normalizeVariantImageMap(map) {
    const normalized = {};
    Object.entries(map || {}).forEach(([code, imageUrl]) => {
      const image = normalizeAliExpressImageUrl(imageUrl);
      if (/^\d{8,14}$/.test(String(code)) && image && looksLikeFinalProductPhotoUrl(image)) {
        normalized[String(code)] = image;
      }
    });
    return normalized;
  }

  function findVariantImage(productInfo, codes) {
    const variantImages = productInfo && productInfo.variantImages ? productInfo.variantImages : {};
    for (const code of codes) {
      const image = variantImages[code];
      if (looksLikeFinalProductPhotoUrl(image)) return image;
    }

    const swatchImage = findSwatchImageByCodeOrder(productInfo, codes);
    if (swatchImage) return swatchImage;

    for (const code of codes) {
      const image = findImageNearVariantCode(productInfo.html || '', code);
      if (image) return image;
    }

    return '';
  }

  function findSwatchImageByCodeOrder(productInfo, codes) {
    const swatchImages = Array.isArray(productInfo && productInfo.swatchImages) ? productInfo.swatchImages : [];
    if (!swatchImages.length || !codes.length) return '';

    const productCodes = extractLikelyVariantCodes(productInfo && productInfo.html);
    for (const code of codes) {
      const index = productCodes.indexOf(code);
      if (index >= 0 && looksLikeFinalProductPhotoUrl(swatchImages[index])) return swatchImages[index];
    }
    return '';
  }

  function extractLikelyVariantCodes(html) {
    return Array.from(new Set(
      String(html || '').match(/\b\d{8,14}\b/g) || []
    )).filter((code) => !/^100\d{10,18}$/.test(code)).slice(0, 80);
  }

  function findImageNearVariantCode(html, code) {
    if (!code) return '';
    const candidates = [];
    let offset = 0;
    while (offset >= 0 && offset < html.length) {
      const index = html.indexOf(code, offset);
      if (index < 0) break;
      const chunk = html.slice(Math.max(0, index - 2500), Math.min(html.length, index + 2500));
      extractAliExpressImageUrls(chunk).forEach((url) => candidates.push(url));
      offset = index + code.length;
      if (candidates.length >= 12) break;
    }
    return candidates
      .filter(looksLikeFinalProductPhotoUrl)
      .sort((a, b) => productImageScore(b) - productImageScore(a))[0] || '';
  }

  function extractAliExpressItemId(value) {
    const text = String(value || '');
    const match = text.match(/(?:\/item\/|itemId=|productId=)(\d{8,20})/i) || text.match(/\b(100\d{10,18})\b/);
    return match ? match[1] : '';
  }

  function recalculateTotalIfNeeded() {
    const current = toNumber(el.total.value);
    const itemSum = sumItems(state.items);
    const currentSubtotal = toNumber(el.subtotal.value);
    const shipping = toNumber(el.shipping.value);
    if (!currentSubtotal || Math.abs(currentSubtotal - itemSum) < 0.01) {
      el.subtotal.value = numberForInput(itemSum);
    }
    if (!current || Math.abs(current - itemSum) < 0.01) {
      el.total.value = numberForInput(itemSum);
    } else if (shipping > 0 && Math.abs(current - (currentSubtotal + shipping)) < 0.01) {
      el.total.value = numberForInput(itemSum + shipping);
    }
  }

  function setDefaultDate() {
    if (!el.orderDate.value) el.orderDate.value = new Date().toISOString().slice(0, 10);
  }

  function setStatus(message, type) {
    el.status.textContent = message;
    el.status.className = `status ${type || 'neutral'}`;
  }

  function toNumber(value) {
    const parsed = Number.parseFloat(String(value || '').replace(',', '.'));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function toNullableNumber(value) {
    if (value === null || value === undefined || value === '') return null;
    const parsed = toNumber(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  function sumItems(items) {
    return roundMoney(items.reduce((sum, item) => sum + (toNumber(item.total) || 0), 0));
  }

  function roundMoney(value) {
    return Math.round((Number(value) || 0) * 100) / 100;
  }

  function numberForInput(value) {
    const number = toNumber(value);
    return number ? String(number) : '';
  }

  function formatDateForOcr(isoDate) {
    const [year, month, day] = String(isoDate || '').split('-');
    return year && month && day ? `${day}/${month}/${year}` : '';
  }

  function formatDecimalComma(value) {
    return (Number(value) || 0).toFixed(2).replace('.', ',');
  }

  function escapeAttr(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function escapeHtml(value) {
    return escapeAttr(value).replace(/'/g, '&#039;');
  }

  function safeFilePart(value) {
    return String(value || 'invoice').replace(/[^a-z0-9_-]+/gi, '-').replace(/^-+|-+$/g, '') || 'invoice';
  }

  function downloadBlob(content, filename, type) {
    const blob = new Blob([content], { type });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    URL.revokeObjectURL(url);
  }
}());