(function () {
  'use strict';

  const STORAGE_PREFIX = 'aliexpressInvoiceDraft:';
  const GEMINI_KEY_STORAGE = 'aliexpressInvoiceGeminiApiKey';
  const BULK_WORKSPACE_STORAGE = 'aliexpressInvoiceBulkWorkspace';
  const SETTINGS_STORAGE = 'aliexpressInvoiceSettings';
  const AI_AUTO_CLEAN_STORAGE = 'aliexpressInvoiceAiAutoClean';
  const AI_NAME_CACHE_STORAGE = 'aliexpressInvoiceAiNameCache';
  const AI_NAME_CACHE_LIMIT = 500;
  const DEFAULT_SETTINGS = {
    defaultDateMode: 'range',
    rangeDays: 30,
    defaultOutputMode: 'separate',
    autoSelectCollectedOrders: true,
    enrichDetailsBeforeOutput: true,
    maxSeparateInvoices: 20,
  };
  const GEMINI_MODELS = [
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-flash-latest',
  ];
  const CONTENT_SCRIPT_VERSION = '0.4.0';
  const imageDimensionCache = new Map();
  // In-memory mirror of the persisted AI cleaned-name cache.
  // Key: `${imageHashOrUrl}|${rawTitle.toLowerCase()}` → cleaned payload.
  const aiNameCache = new Map();
  let aiAutoCleanEnabled = false;
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
    bulkOrders: [],
    bulkMeta: null,
    bulkProgress: null,
    bulkSelection: null,
    settings: { ...DEFAULT_SETTINGS },
  };

  const el = {
    extractButton: document.getElementById('extractButton'),
    addItemButton: document.getElementById('addItemButton'),
    generateButton: document.getElementById('generateButton'),
    downloadJsonButton: document.getElementById('downloadJsonButton'),
    copyTextButton: document.getElementById('copyTextButton'),
    collectBulkButton: document.getElementById('collectBulkButton'),
    openWorkspaceButton: document.getElementById('openWorkspaceButton'),
    generateBulkButton: document.getElementById('generateBulkButton'),
    downloadBulkJsonButton: document.getElementById('downloadBulkJsonButton'),
    bulkFromDate: document.getElementById('bulkFromDate'),
    bulkToDate: document.getElementById('bulkToDate'),
    bulkDateMode: document.getElementById('bulkDateMode'),
    bulkExactDate: document.getElementById('bulkExactDate'),
    bulkExactDateField: document.getElementById('bulkExactDateField'),
    bulkRangeFields: document.getElementById('bulkRangeFields'),
    bulkProgress: document.getElementById('bulkProgress'),
    bulkProgressLabel: document.getElementById('bulkProgressLabel'),
    bulkProgressCount: document.getElementById('bulkProgressCount'),
    bulkProgressBar: document.getElementById('bulkProgressBar'),
    bulkProgressDetail: document.getElementById('bulkProgressDetail'),
    bulkOutputMode: document.getElementById('bulkOutputMode'),
    bulkOrdersList: document.getElementById('bulkOrdersList'),
    settingsDetails: document.getElementById('settingsDetails'),
    settingsDefaultDateMode: document.getElementById('settingsDefaultDateMode'),
    settingsRangeDays: document.getElementById('settingsRangeDays'),
    settingsDefaultOutputMode: document.getElementById('settingsDefaultOutputMode'),
    settingsMaxSeparateInvoices: document.getElementById('settingsMaxSeparateInvoices'),
    settingsAutoSelectOrders: document.getElementById('settingsAutoSelectOrders'),
    settingsEnrichDetails: document.getElementById('settingsEnrichDetails'),
    resetSettingsButton: document.getElementById('resetSettingsButton'),
    applySettingsButton: document.getElementById('applySettingsButton'),
    saveSettingsButton: document.getElementById('saveSettingsButton'),
    aiExtractButton: document.getElementById('aiExtractButton'),
    saveGeminiKeyButton: document.getElementById('saveGeminiKeyButton'),
    geminiApiKey: document.getElementById('geminiApiKey'),
    aiCleanNamesButton: document.getElementById('aiCleanNamesButton'),
    aiAutoCleanToggle: document.getElementById('aiAutoCleanToggle'),
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
    initializePanel();
  });

  async function initializePanel() {
    await loadSettings();
    setDefaultDate();
    setDefaultBulkDates();
    applyWorkspaceUrlParams();
    syncBulkDateModeUi();
    renderBulkProgress();
    loadGeminiKey();
    loadAiAutoCleanPreference();
    loadAiNameCache();
    renderItems();
    restoreBulkWorkspaceState();
    setupBulkWorkspaceStorageListener();
  }

  el.extractButton.addEventListener('click', extractCurrentPage);
  el.aiExtractButton.addEventListener('click', extractCurrentVisibleAreaWithAi);
  el.saveGeminiKeyButton.addEventListener('click', saveGeminiKey);
  if (el.aiCleanNamesButton) {
    el.aiCleanNamesButton.addEventListener('click', () => cleanAllNamesWithAi({ trigger: 'manual' }));
  }
  if (el.aiAutoCleanToggle) {
    el.aiAutoCleanToggle.addEventListener('change', saveAiAutoCleanPreference);
  }
  el.addItemButton.addEventListener('click', () => {
    state.items.push(createEmptyItem());
    renderItems();
    recalculateTotalIfNeeded();
  });
  el.generateButton.addEventListener('click', generateInvoice);
  el.downloadJsonButton.addEventListener('click', downloadJson);
  el.copyTextButton.addEventListener('click', copyOcrText);
  el.openWorkspaceButton.addEventListener('click', () => openBulkWorkspace({ autocollect: false }));
  el.collectBulkButton.addEventListener('click', collectBulkOrders);
  el.generateBulkButton.addEventListener('click', generateBulkInvoices);
  el.downloadBulkJsonButton.addEventListener('click', downloadBulkJson);
  el.saveSettingsButton.addEventListener('click', () => saveSettings({ applyNow: false }));
  el.applySettingsButton.addEventListener('click', () => saveSettings({ applyNow: true }));
  el.resetSettingsButton.addEventListener('click', resetSettings);

  el.bulkDateMode.addEventListener('change', () => {
    syncBulkDateModeUi({ syncInputs: true });
    saveBulkWorkspaceState();
  });
  el.bulkExactDate.addEventListener('change', () => {
    syncBulkDateModeUi({ syncInputs: true });
    saveBulkWorkspaceState();
  });
  el.bulkFromDate.addEventListener('change', () => {
    syncBulkDateModeUi();
    saveBulkWorkspaceState();
  });
  el.bulkToDate.addEventListener('change', () => {
    syncBulkDateModeUi();
    saveBulkWorkspaceState();
  });
  el.bulkOutputMode.addEventListener('change', saveBulkWorkspaceState);
  el.bulkOrdersList.addEventListener('change', (event) => {
    if (event.target && event.target.matches('[data-bulk-check]')) saveBulkWorkspaceState();
  });

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
      // Optional auto-cleanup right after DOM extraction.
      maybeAutoCleanAfter('dom-extract');
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
            case 'ordersList':
              return { ok: true, result: await bridge.extractOrdersList(requestedPayload || {}) };
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

  // ─────────────────────────────────────────────────────────────────────────
  // ✨ AI title cleanup
  //
  // Mirrors `AIAssistantService.cleanProductTitleFromImage` in the ERP
  // (lib/modules/ai_assistant/services/ai_service.dart). Runs at scrape time
  // so the JSON exported by the addon is already shop-friendly. The ERP
  // still has its own fallback cleaner for invoices that don't come from
  // this addon.
  // ─────────────────────────────────────────────────────────────────────────

  async function loadAiAutoCleanPreference() {
    try {
      const stored = await chrome.storage.local.get(AI_AUTO_CLEAN_STORAGE);
      aiAutoCleanEnabled = Boolean(stored[AI_AUTO_CLEAN_STORAGE]);
    } catch (_error) {
      aiAutoCleanEnabled = false;
    }
    if (el.aiAutoCleanToggle) el.aiAutoCleanToggle.checked = aiAutoCleanEnabled;
  }

  async function saveAiAutoCleanPreference() {
    aiAutoCleanEnabled = Boolean(el.aiAutoCleanToggle && el.aiAutoCleanToggle.checked);
    try {
      await chrome.storage.local.set({ [AI_AUTO_CLEAN_STORAGE]: aiAutoCleanEnabled });
    } catch (_error) {/* ignore */}
  }

  async function loadAiNameCache() {
    try {
      const stored = await chrome.storage.local.get(AI_NAME_CACHE_STORAGE);
      const raw = stored[AI_NAME_CACHE_STORAGE];
      if (raw && typeof raw === 'object') {
        Object.entries(raw).forEach(([k, v]) => {
          if (v && typeof v === 'object') aiNameCache.set(k, v);
        });
      }
    } catch (_error) {/* ignore */}
  }

  async function persistAiNameCache() {
    try {
      // Bound the cache so chrome.storage.local doesn't grow unbounded.
      if (aiNameCache.size > AI_NAME_CACHE_LIMIT) {
        const overflow = aiNameCache.size - AI_NAME_CACHE_LIMIT;
        const it = aiNameCache.keys();
        for (let i = 0; i < overflow; i++) {
          const next = it.next();
          if (next.done) break;
          aiNameCache.delete(next.value);
        }
      }
      const obj = {};
      aiNameCache.forEach((v, k) => { obj[k] = v; });
      await chrome.storage.local.set({ [AI_NAME_CACHE_STORAGE]: obj });
    } catch (_error) {/* ignore */}
  }

  function aiCacheKeyFor(rawTitle, imageUrl) {
    const t = String(rawTitle || '').trim().toLowerCase();
    const i = String(imageUrl || '').trim();
    return `${i || 'noimg'}|${t}`;
  }

  async function fetchImageAsBase64(imageUrl) {
    if (!imageUrl) return null;
    try {
      const response = await fetch(imageUrl, { method: 'GET' });
      if (!response.ok) return null;
      const blob = await response.blob();
      // Skip absurdly large images so we don't blow Gemini quotas.
      if (blob.size > 4 * 1024 * 1024) return null;
      const arrayBuf = await blob.arrayBuffer();
      const bytes = new Uint8Array(arrayBuf);
      let binary = '';
      const chunk = 0x8000;
      for (let i = 0; i < bytes.length; i += chunk) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
      }
      const mime = blob.type && blob.type.startsWith('image/') ? blob.type : 'image/jpeg';
      return { base64: btoa(binary), mime };
    } catch (_error) {
      return null;
    }
  }

  function buildCleanNamePrompt(rawTitle, supplierName) {
    const sup = supplierName ? ` (proveedor: ${supplierName})` : '';
    return [
      'Eres un asistente experto en taller de bicicletas en Chile.',
      `Recibes el titulo bruto de un producto AliExpress${sup} y, cuando esta disponible, una foto.`,
      'Tu tarea: reescribirlo como un nombre CORTO, claro y consistente para el catalogo de un taller chileno.',
      '',
      'Reglas:',
      '- Maximo 60 caracteres.',
      '- Empieza por el componente en singular y en espanol chileno de taller (postiza, polea, plato, piola, pastilla, camara, cassette, cadena, manilla, eslabon, etc.).',
      '- Si la marca es clara, agregala (ZTTO, Shimano, KMC, SRAM, RISK, ENLEE, ODI, etc.). Si no, deja el campo brand vacio.',
      '- Si el modelo es claro, agregalo (ej. "001", "M-310", "HG-200", "9v").',
      '- IMPORTANTE: NO incluyas cantidad de empaque ni multiplicadores en el nombre. Quita expresiones como "Set 5", "5 pares", "100 unidades", "(50 unidades)", "pack 10", "x4", "4pcs", "kit 3". El nombre describe UNA unidad del producto.',
      '- Si el producto es naturalmente plural (ej. "Pastillas de freno", "Pernos"), conserva esa forma sin numeros.',
      '- NO copies marketing como "for MTB Bike Bicycle Universal Steel Aluminum 2024 New".',
      '- NO inventes datos que no estan en titulo o imagen.',
      '- category_name debe ser una categoria humana, simple, en plural, en espanol chileno de taller (ej. "Pastillas", "Cadenas", "Eslabones", "Postizas", "Pedales", "Puños", "Pernos", "Cassettes", "Rotores", "Camaras", "Herramientas"). Una sola palabra cuando sea posible.',
      '- Devuelve SOLO un objeto JSON valido con esta forma EXACTA, sin texto adicional:',
      '  {"cleaned_name": "Postiza ZTTO 001", "component_type": "postiza", "brand": "ZTTO", "model": "001", "category_name": "Postizas", "confidence": 0.0-1.0}',
      '',
      `Titulo bruto: ${rawTitle}`,
    ].join('\n');
  }

  function parseCleanedNameJson(payload) {
    const text = (payload && payload.candidates && payload.candidates[0]
      && payload.candidates[0].content && payload.candidates[0].content.parts)
      ? payload.candidates[0].content.parts.map((p) => p.text || '').join('\n')
      : '';
    if (!text) return null;
    let obj;
    try {
      obj = JSON.parse(text);
    } catch (_error) {
      const match = text.match(/\{[\s\S]*\}/);
      if (!match) return null;
      try { obj = JSON.parse(match[0]); } catch (_e2) { return null; }
    }
    const coerce = (v, max = 80) => {
      if (v == null) return '';
      let s = String(v).trim().replace(/\s+/g, ' ');
      if (s.length > max) s = s.slice(0, max).trim();
      return s;
    };
    const cleanedName = coerce(obj.cleaned_name, 80);
    if (!cleanedName) return null;
    const conf = Number(obj.confidence);
    return {
      cleanedName,
      componentType: coerce(obj.component_type, 40).toLowerCase(),
      brand: coerce(obj.brand, 40),
      model: coerce(obj.model, 40),
      categoryName: coerce(obj.category_name, 60),
      confidence: Number.isFinite(conf) ? Math.max(0, Math.min(1, conf)) : 0.6,
    };
  }

  async function aiCleanProductTitle(apiKey, { rawTitle, imageUrl, supplierName }) {
    const trimmed = String(rawTitle || '').trim();
    if (!trimmed) return null;

    const cacheKey = aiCacheKeyFor(trimmed, imageUrl);
    if (aiNameCache.has(cacheKey)) return aiNameCache.get(cacheKey);

    const parts = [{ text: buildCleanNamePrompt(trimmed, supplierName) }];
    const imagePart = await fetchImageAsBase64(imageUrl);
    if (imagePart) {
      parts.push({ inline_data: { mime_type: imagePart.mime, data: imagePart.base64 } });
    }

    const { payload } = await callGeminiGenerateContent(apiKey, {
      contents: [{ role: 'user', parts }],
      generationConfig: {
        temperature: 0.2,
        response_mime_type: 'application/json',
      },
    });

    const result = parseCleanedNameJson(payload);
    if (result) {
      aiNameCache.set(cacheKey, result);
      // Fire-and-forget; persisting on every hit is fine because the addon
      // never runs more than a few dozen rows in parallel.
      persistAiNameCache();
    }
    return result;
  }

  function applyAiCleanedNameToItem(item, cleaned) {
    if (!item || !cleaned || !cleaned.cleanedName) return false;
    const original = String(item.originalDescription || item.description || '').trim();
    item.originalDescription = original;
    item.description = cleaned.cleanedName;
    item.aiCleaned = true;
    item.aiCategory = cleaned.categoryName || '';
    item.aiBrand = cleaned.brand || '';
    item.aiModel = cleaned.model || '';
    item.aiComponent = cleaned.componentType || '';
    item.aiConfidence = cleaned.confidence;
    return true;
  }

  // Run the cleaner over `state.items` (single invoice) and over every
  // selected bulk order's items. Cap concurrency so we don't hammer Gemini.
  async function cleanAllNamesWithAi({ trigger = 'manual', concurrency = 3 } = {}) {
    const apiKey = (el.geminiApiKey && el.geminiApiKey.value || '').trim();
    if (!apiKey) {
      if (trigger === 'manual') {
        setStatus('Pega tu Gemini API key y pulsa Guardar antes de limpiar nombres.', 'error');
      }
      return { processed: 0, total: 0 };
    }

    const supplierName = (el.supplierName && el.supplierName.value || '').trim() || 'AliExpress Marketplace';

    // Collect every item that hasn't been AI-cleaned and isn't user-edited.
    const targets = [];
    state.items.forEach((item, idx) => {
      if (!item || item.aiCleaned) return;
      const raw = String(item.originalDescription || item.description || '').trim();
      if (!raw) return;
      targets.push({ item, scope: 'single', idx, raw });
    });
    if (Array.isArray(state.bulkOrders)) {
      state.bulkOrders.forEach((order, oIdx) => {
        if (!order || !Array.isArray(order.items)) return;
        order.items.forEach((item, iIdx) => {
          if (!item || item.aiCleaned) return;
          const raw = String(item.originalDescription || item.description || '').trim();
          if (!raw) return;
          targets.push({ item, scope: 'bulk', oIdx, iIdx, raw });
        });
      });
    }

    if (targets.length === 0) {
      if (trigger === 'manual') setStatus('No hay nombres pendientes de limpiar.', 'neutral');
      return { processed: 0, total: 0 };
    }

    if (el.aiCleanNamesButton) el.aiCleanNamesButton.disabled = true;
    setStatus(`Limpiando ${targets.length} nombre(s) con Gemini...`, 'neutral');

    let done = 0;
    let failures = 0;
    const queue = targets.slice();
    const workers = Array.from({ length: Math.max(1, Math.min(concurrency, targets.length)) }, async () => {
      while (queue.length > 0) {
        const next = queue.shift();
        if (!next) break;
        try {
          const cleaned = await aiCleanProductTitle(apiKey, {
            rawTitle: next.raw,
            imageUrl: next.item.imageUrl || '',
            supplierName,
          });
          if (cleaned) applyAiCleanedNameToItem(next.item, cleaned);
        } catch (error) {
          failures += 1;
          // Surface only the first error in the status line; keep going.
          if (failures === 1) {
            console.warn('[AliExpress AI cleanup] Gemini call failed:', error && error.message ? error.message : error);
          }
        } finally {
          done += 1;
          if (done % 3 === 0 || done === targets.length) {
            setStatus(`Limpiando nombres con IA... ${done}/${targets.length}`, 'neutral');
          }
        }
      }
    });
    await Promise.all(workers);

    // Re-render any view that may show stale text.
    renderItems();
    if (typeof renderBulkOrders === 'function') {
      try { renderBulkOrders(); } catch (_e) {/* ignore */}
    }
    // Persist the bulk workspace so the cleaned names survive panel reloads.
    if (typeof saveBulkWorkspaceState === 'function' && Array.isArray(state.bulkOrders) && state.bulkOrders.length) {
      try { await saveBulkWorkspaceState(); } catch (_e) {/* ignore */}
    }

    const tone = failures === 0 ? 'success' : 'warning';
    const msg = failures === 0
      ? `Limpieza IA lista: ${done}/${targets.length} nombre(s) actualizado(s).`
      : `Limpieza IA: ${done - failures}/${targets.length} ok, ${failures} fallaron (revisa la consola).`;
    setStatus(msg, tone);
    if (el.aiCleanNamesButton) el.aiCleanNamesButton.disabled = false;
    return { processed: done - failures, total: targets.length, failures };
  }

  async function maybeAutoCleanAfter(trigger) {
    if (!aiAutoCleanEnabled) return;
    const apiKey = (el.geminiApiKey && el.geminiApiKey.value || '').trim();
    if (!apiKey) return;
    try {
      await cleanAllNamesWithAi({ trigger });
    } catch (error) {
      console.warn('[AliExpress AI cleanup] Auto cleanup failed:', error);
    }
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
      // Optional auto-cleanup right after AI extraction when the user opted in.
      maybeAutoCleanAfter('ai-ocr');
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
      const domTokens = tokenize([dom.description, dom.originalDescription].filter(Boolean).join(' '));
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
      if (!el.orderDate.value && domOrder.orderDate) el.orderDate.value = domOrder.orderDate;
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
    el.orderDate.value = order.orderDate || '';
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
            Linea ${index + 1}${item.aiCleaned ? ' <span class="ai-clean-badge" title="Nombre limpiado por IA. Original: '
              + escapeAttr(String(item.originalDescription || '')) + '">✨ IA</span>' : ''}
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

  async function collectBulkOrders() {
    if (!isWorkspaceMode()) {
      setStatus('Abriendo panel estable y empezando colecta...', 'neutral');
      await openBulkWorkspace({ autocollect: true });
      return;
    }

    const filters = getBulkDateFilters({ syncInputs: true });
    setStatus('Colectando ordenes cargadas en la lista de AliExpress...', 'neutral');
    setBulkProgress({
      active: true,
      label: 'Colectando ordenes',
      detail: filters.label,
      percent: 18,
      type: 'active',
    });
    el.collectBulkButton.disabled = true;
    el.generateBulkButton.disabled = true;

    try {
      await saveBulkWorkspaceState('Colectando ordenes cargadas en la lista de AliExpress...', 'neutral');
      const tab = await getAliExpressSourceTab();
      if (!tab || !tab.id) throw new Error('No se encontro una pestana activa.');
      if (!/^https:\/\/([^/]+\.)?aliexpress\.com\//i.test(tab.url || '')) {
        throw new Error('Abre Account > Orders en AliExpress antes de colectar.');
      }

      await ensureFreshContentBridge(tab.id);
      setBulkProgress({ active: true, label: 'Leyendo lista AliExpress', detail: 'Escaneando ordenes visibles y View orders.', percent: 42, type: 'active' });
      const response = await executeContentCommand(tab.id, 'ordersList', filters);

      if (!response || !response.ok) {
        throw new Error(response && response.error ? response.error : 'No se pudo colectar la lista de ordenes.');
      }

      const result = response.result || {};
      state.bulkMeta = {
        pageUrl: result.pageUrl || tab.url || '',
        collectedAt: result.collectedAt || new Date().toISOString(),
        scannedCount: result.scannedCount || 0,
        dateMode: result.dateMode || filters.dateMode,
        exactDate: result.exactDate || filters.exactDate || '',
        fromDate: result.fromDate || filters.fromDate || '',
        toDate: result.toDate || filters.toDate || '',
        preload: result.preload || null,
        warnings: result.warnings || [],
      };
      state.bulkOrders = Array.isArray(result.orders) ? result.orders.map(normalizeBulkInvoice) : [];
      state.bulkSelection = state.settings.autoSelectCollectedOrders
        ? state.bulkOrders.map(bulkOrderSelectionKey).filter(Boolean)
        : [];
      renderBulkOrders();
      await saveBulkWorkspaceState();

      const warningText = state.bulkMeta.warnings.length ? ` ${state.bulkMeta.warnings.join(' ')}` : '';
      const statusType = state.bulkOrders.length > 0 ? (state.bulkMeta.warnings.length ? 'warning' : 'success') : 'warning';
      const loadText = state.bulkMeta.preload && state.bulkMeta.preload.loadMoreClicks
        ? ` Se abrio View orders ${state.bulkMeta.preload.loadMoreClicks} vez/veces.`
        : '';
      setBulkProgress({
        active: false,
        label: state.bulkOrders.length > 0 ? 'Bulk listo' : 'Sin ordenes en rango',
        detail: `${state.bulkOrders.length}/${state.bulkMeta.scannedCount} orden(es). ${filters.label}${loadText}`,
        percent: 100,
        type: statusType,
      });
      setStatus(`Bulk listo: ${state.bulkOrders.length}/${state.bulkMeta.scannedCount} orden(es) en rango.${loadText}${warningText}`, statusType);
      await saveBulkWorkspaceState(`Bulk listo: ${state.bulkOrders.length}/${state.bulkMeta.scannedCount} orden(es) en rango.${loadText}${warningText}`, statusType);
      // Optional auto-cleanup right after bulk collect.
      maybeAutoCleanAfter('bulk-collect');
    } catch (error) {
      setBulkProgress({ active: false, label: 'Bulk fallo', detail: error.message || String(error), percent: 100, type: 'error' });
      setStatus(error.message || String(error), 'error');
      await saveBulkWorkspaceState(error.message || String(error), 'error');
    } finally {
      el.collectBulkButton.disabled = false;
      el.generateBulkButton.disabled = false;
    }
  }

  function renderBulkOrders() {
    if (!el.bulkOrdersList) return;
    if (!state.bulkOrders.length) {
      el.bulkOrdersList.innerHTML = '<p class="status neutral">Sin ordenes colectadas. Abre la lista de AliExpress y pulsa Colectar.</p>';
      return;
    }

    el.bulkOrdersList.innerHTML = state.bulkOrders.map((order, index) => `
      <label class="bulk-order-row" data-bulk-index="${index}">
        <input type="checkbox" data-bulk-check="${index}" ${isBulkOrderSelected(order) ? 'checked' : ''}>
        <span class="bulk-order-main">
          <strong># ${escapeHtml(order.orderNumber || `Orden ${index + 1}`)}</strong>
          <span class="bulk-order-meta">${escapeHtml(order.orderDate || '')} · ${order.items.length} linea(s)</span>
          <span class="bulk-order-meta">${escapeHtml(firstOrderItemTitle(order))}</span>
        </span>
        <span class="bulk-order-total">$ ${escapeHtml(formatDecimalComma(order.total || sumItems(order.items)))}</span>
      </label>
    `).join('');
  }

  function isBulkOrderSelected(order) {
    if (!Array.isArray(state.bulkSelection)) return state.settings.autoSelectCollectedOrders;
    const key = bulkOrderSelectionKey(order);
    return state.bulkSelection.includes(key);
  }

  function bulkOrderSelectionKey(order) {
    return String((order && order.orderNumber) || (order && order.pageUrl) || '').trim();
  }

  function firstOrderItemTitle(order) {
    const item = order && order.items && order.items[0] ? order.items[0] : null;
    if (!item) return 'Sin descripcion';
    return String(item.description || item.sku || 'Sin descripcion').slice(0, 90);
  }

  function selectedBulkOrders() {
    const checked = Array.from(el.bulkOrdersList.querySelectorAll('[data-bulk-check]:checked'))
      .map((input) => state.bulkOrders[Number(input.dataset.bulkCheck)])
      .filter(Boolean);
    return checked.length ? checked : [];
  }

  async function generateBulkInvoices() {
    let orders = selectedBulkOrders();
    if (!orders.length) {
      setStatus('Selecciona al menos una orden bulk para generar PDFs.', 'error');
      return;
    }

    el.generateBulkButton.disabled = true;
    try {
      await saveBulkWorkspaceState('Generando bulk...', 'neutral');
      setBulkProgress({ active: true, label: 'Preparando bulk', detail: `${orders.length} orden(es) seleccionadas.`, percent: 8, type: 'active' });
      const mode = el.bulkOutputMode ? el.bulkOutputMode.value : 'separate';
      orders = await maybeEnrichBulkOrdersFromDetails(orders, { force: mode === 'combined' });
      if (mode === 'combined') {
        const invoice = buildCombinedBulkInvoice(orders);
        const validationError = validateInvoice(invoice);
        if (validationError) throw new Error(validationError);
        await openInvoiceDraft(invoice, true);
        setBulkProgress({ active: false, label: 'Factura consolidada lista', detail: `${orders.length} orden(es), ${invoice.items.length} linea(s).`, percent: 100, type: 'success' });
        setStatus(`Factura consolidada creada con ${orders.length} orden(es) y ${invoice.items.length} linea(s).`, 'success');
        await saveBulkWorkspaceState(`Factura consolidada creada con ${orders.length} orden(es) y ${invoice.items.length} linea(s).`, 'success');
        return;
      }

      const maxTabs = state.settings.maxSeparateInvoices;
      const limited = orders.slice(0, maxTabs);
      const exactInvoiceDate = selectedBulkExactInvoiceDate();
      for (let index = 0; index < limited.length; index += 1) {
        setBulkProgress({ active: true, label: 'Generando PDFs', detail: `${index + 1}/${limited.length}: ${limited[index].orderNumber || 'orden AliExpress'}`, current: index, total: limited.length, type: 'active' });
        await openInvoiceDraft(applyGeneratedInvoiceDate(normalizeBulkInvoice(limited[index]), exactInvoiceDate), false);
      }
      const suffix = orders.length > maxTabs ? ` Se abrieron las primeras ${maxTabs}; reduce seleccion para el resto.` : '';
      setBulkProgress({ active: false, label: 'PDFs generados', detail: `${limited.length} factura(s).${suffix}`, percent: 100, type: orders.length > maxTabs ? 'warning' : 'success' });
      setStatus(`Se generaron ${limited.length} factura(s) en pestanas nuevas.${suffix}`, orders.length > maxTabs ? 'warning' : 'success');
      await saveBulkWorkspaceState(`Se generaron ${limited.length} factura(s) en pestanas nuevas.${suffix}`, orders.length > maxTabs ? 'warning' : 'success');
    } catch (error) {
      setBulkProgress({ active: false, label: 'Generacion fallo', detail: error.message || String(error), percent: 100, type: 'error' });
      setStatus(error.message || String(error), 'error');
      await saveBulkWorkspaceState(error.message || String(error), 'error');
    } finally {
      el.generateBulkButton.disabled = false;
    }
  }

  async function enrichBulkOrdersFromDetails(orders) {
    const result = [];
    state.lastEnrichmentDebug = []; // [v0.3.50 DEBUG] reset audit log per batch
    setBulkProgress({ active: true, label: 'Leyendo detalles', detail: `0/${orders.length}`, current: 0, total: orders.length, type: 'active' });
    for (let index = 0; index < orders.length; index += 1) {
      const listOrder = normalizeBulkInvoice(orders[index]);
      const detailUrl = resolveOrderDetailUrl(listOrder);
      if (!detailUrl) {
        result.push({
          ...listOrder,
          warnings: [...(listOrder.warnings || []), 'No se encontro URL de detalle; se uso la informacion visible en la lista.'],
        });
        continue;
      }

      setStatus(`Enriqueciendo detalle ${index + 1}/${orders.length}: ${listOrder.orderNumber || 'orden AliExpress'}...`, 'neutral');
        setBulkProgress({ active: true, label: 'Leyendo detalles', detail: `${index + 1}/${orders.length}: ${listOrder.orderNumber || 'orden AliExpress'}`, current: index, total: orders.length, type: 'active' });
      await saveBulkWorkspaceState(`Enriqueciendo detalle ${index + 1}/${orders.length}: ${listOrder.orderNumber || 'orden AliExpress'}...`, 'neutral');
      let detailTab = null;
      try {
        detailTab = await chrome.tabs.create({ url: detailUrl, active: false });
        await waitForTabComplete(detailTab.id, 18000);
        await ensureFreshContentBridge(detailTab.id);
        const response = await executeContentCommand(detailTab.id, 'extract');
        if (!response || !response.ok || !response.order) throw new Error(response && response.error ? response.error : 'Detalle sin datos.');
        const detailOrder = response.order;
        // [v0.3.50 DEBUG] Per-order enrichment audit. Open popup DevTools (right-click popup -> Inspect) to view.
        try {
          const audit = {
            orderNumber: detailOrder.orderNumber || listOrder.orderNumber || '',
            detailUrl,
            list: { subtotal: listOrder.subtotal, shipping: listOrder.shipping, tax: listOrder.tax, discount: listOrder.discount, total: listOrder.total },
            detail: { subtotal: detailOrder.subtotal, shipping: detailOrder.shipping, tax: detailOrder.tax, discount: detailOrder.discount, total: detailOrder.total },
            balance: (() => {
              const sub = Number(detailOrder.subtotal) || 0;
              const ship = Number(detailOrder.shipping) || 0;
              const tax = Number(detailOrder.tax) || 0;
              const disc = Number(detailOrder.discount) || 0;
              const tot = Number(detailOrder.total) || 0;
              const calc = Math.round((sub + ship + tax - disc) * 100) / 100;
              return { calc, total: tot, residual: Math.round((tot - calc) * 100) / 100 };
            })(),
            rawTextPreview: (detailOrder.rawTextPreview || '').slice(0, 2500),
            expandDebug: detailOrder.__expandDebug || null,
          };
          // eslint-disable-next-line no-console
          console.log('[AE-INV 0.3.51] enrichment audit', audit);
          state.lastEnrichmentDebug = state.lastEnrichmentDebug || [];
          state.lastEnrichmentDebug.push(audit);
          try { await chrome.storage.local.set({ aliExpressLastEnrichmentDebug: state.lastEnrichmentDebug }); } catch (_) { /* ignore */ }
        } catch (_) { /* never let debug break enrichment */ }
        const merged = mergeBulkListAndDetailOrder(listOrder, detailOrder, detailUrl);
        result.push(merged);
      } catch (error) {
        result.push({
          ...listOrder,
          warnings: [...(listOrder.warnings || []), `No se pudo leer detalle (${error.message || String(error)}); se uso la informacion visible en la lista.`],
        });
      } finally {
        if (detailTab && detailTab.id) {
          try { await chrome.tabs.remove(detailTab.id); } catch (_) { /* tab already closed */ }
        }
        setBulkProgress({ active: true, label: 'Leyendo detalles', detail: `${Math.min(index + 1, orders.length)}/${orders.length}`, current: index + 1, total: orders.length, type: 'active' });
      }
    }

    state.bulkOrders = result.map(normalizeBulkInvoice);
    renderBulkOrders();
    await saveBulkWorkspaceState();
    return state.bulkOrders;
  }

  async function maybeEnrichBulkOrdersFromDetails(orders, options = {}) {
    if (options.force || state.settings.enrichDetailsBeforeOutput) return enrichBulkOrdersFromDetails(orders);
    setBulkProgress({
      active: false,
      label: 'Usando datos de lista',
      detail: 'Lectura de detalles desactivada en Ajustes.',
      percent: 100,
      type: 'warning',
    });
    return orders.map(normalizeBulkInvoice);
  }

  function resolveOrderDetailUrl(order) {
    const pageUrl = String(order && order.pageUrl || '').trim();
    if (isUsableOrderDetailUrl(pageUrl, order && order.orderNumber)) return pageUrl;
    const orderNumber = String(order && order.orderNumber || '').replace(/\D+/g, '');
    return orderNumber ? `https://www.aliexpress.com/p/order/detail.html?orderId=${encodeURIComponent(orderNumber)}` : '';
  }

  function isUsableOrderDetailUrl(url, orderNumber) {
    const value = String(url || '');
    if (!/^https:\/\/([^/]+\.)?aliexpress\.com\//i.test(value)) return false;
    if (/\/p\/order\/index\.html/i.test(value)) return false;
    if (/order.*detail|detail.*order|orderId|order_id|orderIdList/i.test(value)) return true;
    const digits = String(orderNumber || '').replace(/\D+/g, '');
    return Boolean(digits && value.includes(digits));
  }

  function waitForTabComplete(tabId, timeoutMs) {
    return new Promise((resolve, reject) => {
      let done = false;
      const timeout = window.setTimeout(() => finish(false), timeoutMs || 15000);
      const listener = (updatedTabId, changeInfo) => {
        if (updatedTabId === tabId && changeInfo.status === 'complete') finish(true);
      };
      function finish(success) {
        if (done) return;
        done = true;
        window.clearTimeout(timeout);
        chrome.tabs.onUpdated.removeListener(listener);
        success ? resolve() : reject(new Error('Timeout cargando detalle AliExpress.'));
      }
      chrome.tabs.onUpdated.addListener(listener);
      chrome.tabs.get(tabId, (tab) => {
        if (chrome.runtime.lastError) return;
        if (tab && tab.status === 'complete') finish(true);
      });
    });
  }

  function mergeBulkListAndDetailOrder(listOrder, detailOrder, detailUrl) {
    const detail = normalizeBulkInvoice(detailOrder);
    const list = normalizeBulkInvoice(listOrder);
    const detailItems = detail.items.filter((item) => item.description || item.sku);
    const listItems = list.items.filter((item) => item.description || item.sku);
    const useDetailItems = detailItems.length >= listItems.length || detailItems.some((item) => item.imageUrl);
    const items = useDetailItems ? detailItems : listItems;
    const subtotal = toNullableNumber(detail.subtotal) ?? toNullableNumber(list.subtotal) ?? sumItems(items);
    const total = toNullableNumber(detail.total) ?? toNullableNumber(list.total) ?? roundMoney(sumItems(items) + (toNullableNumber(detail.shipping) || toNullableNumber(list.shipping) || 0));

    const warnings = [...(list.warnings || []), ...(detail.warnings || [])];
    if (toNullableNumber(detail.total) !== null && toNullableNumber(detail.subtotal) !== null) {
      const missing = ['shipping', 'tax', 'discount'].filter((field) => toNullableNumber(detail[field]) === null);
      if (missing.length) {
        warnings.push(`Detalle AliExpress incompleto: no se pudo leer ${missing.join(', ')} desde la pagina de detalle.`);
      }
    }

    // [v0.3.51] When the detail page produced an authoritative balanced totals card,
    // its null shipping/tax/discount mean "definitively absent" and must NOT fall back to
    // the noisy list-page values (those often misread promo/coupon copy as a discount).
    const detailAuthoritative = detailOrder && detailOrder.__authoritativeTotals === true;
    const pickComponent = (field) => {
      const detailValue = toNullableNumber(detail[field]);
      if (detailValue !== null) return detailValue;
      if (detailAuthoritative) return null;
      return toNullableNumber(list[field]);
    };

    return {
      ...list,
      ...detail,
      pageUrl: detail.pageUrl || detailUrl || list.pageUrl,
      pageTitle: detail.pageTitle || list.pageTitle,
      orderNumber: detail.orderNumber || list.orderNumber,
      orderDate: detail.orderDate || list.orderDate,
      supplierName: detail.supplierName || list.supplierName || 'AliExpress Marketplace',
      supplierTaxId: detail.supplierTaxId || list.supplierTaxId || '',
      subtotal,
      shipping: pickComponent('shipping'),
      tax: pickComponent('tax'),
      discount: pickComponent('discount'),
      total,
      notes: [detail.notes || list.notes || '', `Detalle enriquecido desde: ${detailUrl}`].filter(Boolean).join('\n'),
      items,
      warnings,
    };
  }

  async function downloadBulkJson() {
    let orders = selectedBulkOrders();
    if (!orders.length) {
      setStatus('Selecciona al menos una orden bulk para exportar JSON.', 'error');
      return;
    }

    el.downloadBulkJsonButton.disabled = true;
    try {
      await saveBulkWorkspaceState('Exportando JSON bulk...', 'neutral');
      setBulkProgress({ active: true, label: 'Exportando JSON', detail: `${orders.length} orden(es) seleccionadas.`, percent: 8, type: 'active' });
      orders = await maybeEnrichBulkOrdersFromDetails(orders);
      const combined = orders.length ? buildCombinedBulkInvoice(orders) : null;
      downloadBlob(
        JSON.stringify({ meta: state.bulkMeta, orders: orders.map(normalizeBulkInvoice), combined }, null, 2),
        `aliexpress-bulk-${safeFilePart(el.bulkFromDate.value || 'from')}-${safeFilePart(el.bulkToDate.value || 'to')}.json`,
        'application/json',
      );
      setBulkProgress({ active: false, label: 'JSON exportado', detail: `${orders.length} orden(es) enriquecidas.`, percent: 100, type: 'success' });
      setStatus(`JSON bulk exportado con ${orders.length} orden(es) enriquecidas.`, 'success');
      await saveBulkWorkspaceState(`JSON bulk exportado con ${orders.length} orden(es) enriquecidas.`, 'success');
    } catch (error) {
      setBulkProgress({ active: false, label: 'Exportacion fallo', detail: error.message || String(error), percent: 100, type: 'error' });
      setStatus(error.message || String(error), 'error');
      await saveBulkWorkspaceState(error.message || String(error), 'error');
    } finally {
      el.downloadBulkJsonButton.disabled = false;
    }
  }

  async function openInvoiceDraft(invoice, active) {
    const validationError = validateInvoice(invoice);
    if (validationError) throw new Error(`# ${invoice.orderNumber || 'orden'}: ${validationError}`);
    const draftId = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    await chrome.storage.local.set({ [`${STORAGE_PREFIX}${draftId}`]: invoice });
    await chrome.tabs.create({ url: chrome.runtime.getURL(`invoice.html?draft=${encodeURIComponent(draftId)}`), active: Boolean(active) });
  }

  function allocateInvoiceComponents(invoice) {
    const items = Array.isArray(invoice.items) ? invoice.items.map(normalizeItem).filter((item) => item.description || item.sku) : [];
    if (!items.length) return { ...invoice, items };

    const sourceTotals = items.map(sourceItemTotal);
    const calculatedSubtotal = roundMoney(sourceTotals.reduce((sum, value) => sum + value, 0));
    const providedSubtotal = toNullableNumber(invoice.subtotal);
    const subtotal = calculatedSubtotal > (providedSubtotal || 0)
      ? calculatedSubtotal
      : (providedSubtotal ?? calculatedSubtotal);
    const hasKnownShipping = toNullableNumber(invoice.shipping) !== null;
    const hasKnownTax = toNullableNumber(invoice.tax) !== null;
    let shipping = positiveComponentAmount(invoice.shipping);
    let tax = positiveComponentAmount(invoice.tax);
    let discount = positiveComponentAmount(invoice.discount);
    const statedTotal = toNullableNumber(invoice.total);

    if (statedTotal !== null) {
      const componentTotal = roundMoney(subtotal + shipping + tax - discount);
      const residual = roundMoney(statedTotal - componentTotal);
      // [v0.3.51] Only fabricate a missing component when the gap is large enough that it
      // is clearly a real missing line (shipping / tax / discount). Small gaps (CLP rounding,
      // ~$1-$50 on a multi-thousand-CLP order) are absorbed silently by the per-row adjustment
      // below at line ~1325, so we never invent a fake discount that mirrors shipping.
      const fabricationThreshold = Math.max(50, Math.abs(statedTotal) * 0.02);
      if (residual > fabricationThreshold) {
        if (!hasKnownTax && hasKnownShipping) {
          tax = roundMoney(tax + residual);
        } else if (!hasKnownShipping && hasKnownTax) {
          shipping = roundMoney(shipping + residual);
        } else if (!hasKnownShipping && !hasKnownTax) {
          tax = roundMoney(tax + residual);
        } else {
          tax = roundMoney(tax + residual);
        }
      } else if (residual < -fabricationThreshold) {
        discount = roundMoney(discount + Math.abs(residual));
      }
    }

    const finalTotal = statedTotal ?? roundMoney(subtotal + shipping + tax - discount);
    const basis = sourceTotals.some((value) => value > 0)
      ? sourceTotals
      : items.map(() => 1);
    const shippingAllocations = allocateByWeight(shipping, basis);
    const taxAllocations = allocateByWeight(tax, basis);
    const discountAllocations = allocateByWeight(discount, basis);
    const allocatedItems = items.map((item, index) => {
      const quantity = toNumber(item.quantity) || 1;
      const sourceTotal = sourceTotals[index] || roundMoney(sourceItemUnitPrice(item) * quantity);
      const sourceUnitPrice = roundMoney(sourceTotal / quantity) || sourceItemUnitPrice(item);
      const allocatedShippingTotal = shippingAllocations[index] || 0;
      const allocatedTaxTotal = taxAllocations[index] || 0;
      const allocatedDiscountTotal = discountAllocations[index] || 0;
      const allocatedShipping = roundMoney(allocatedShippingTotal / quantity);
      const allocatedTax = roundMoney(allocatedTaxTotal / quantity);
      const allocatedDiscount = roundMoney(allocatedDiscountTotal / quantity);
      const unitPrice = Math.max(0, roundMoney(sourceUnitPrice + allocatedShipping + allocatedTax - allocatedDiscount));
      const total = roundMoney(unitPrice * quantity);
      return {
        ...item,
        sourceUnitPrice,
        sourceTotal,
        allocatedShipping,
        allocatedTax,
        allocatedDiscount,
        allocatedShippingTotal,
        allocatedTaxTotal,
        allocatedDiscountTotal,
        allocationGranularity: 'unit',
        unitPrice,
        total,
      };
    });

    const allocatedRowTotal = sumItems(allocatedItems);
    const residual = roundMoney(finalTotal - allocatedRowTotal);
    if (Math.abs(residual) >= 0.01 && allocatedItems.length) {
      const targetIndex = largestSourceTotalIndex(sourceTotals);
      const target = allocatedItems[targetIndex];
      const adjustedTotal = roundMoney(target.total + residual);
      allocatedItems[targetIndex] = {
        ...target,
        total: adjustedTotal,
        unitPrice: roundMoney(adjustedTotal / (toNumber(target.quantity) || 1)),
      };
    }

    return {
      ...invoice,
      subtotal,
      shipping: shipping || null,
      tax: tax || null,
      discount: discount || null,
      total: finalTotal,
      items: allocatedItems,
      allocation: {
        method: 'weighted_by_product_total',
        sourceSubtotal: subtotal,
        shipping,
        tax,
        discount,
        finalTotal,
      },
    };
  }

  function sourceItemUnitPrice(item) {
    const quantity = toNumber(item.quantity) || 1;
    const explicitSourceUnit = toNullableNumber(item.sourceUnitPrice);
    if (explicitSourceUnit !== null) return explicitSourceUnit;
    const explicitSourceTotal = toNullableNumber(item.sourceTotal);
    if (explicitSourceTotal !== null) return roundMoney(explicitSourceTotal / quantity);
    return toNumber(item.unitPrice);
  }

  function sourceItemTotal(item) {
    const explicitSourceTotal = toNullableNumber(item.sourceTotal);
    if (explicitSourceTotal !== null) return explicitSourceTotal;
    const quantity = toNumber(item.quantity) || 1;
    const sourceUnit = sourceItemUnitPrice(item);
    const calculatedTotal = roundMoney(sourceUnit * quantity);
    return calculatedTotal || toNumber(item.total);
  }

  function positiveComponentAmount(value) {
    const number = toNullableNumber(value);
    return number === null ? 0 : Math.abs(number);
  }

  function allocateByWeight(amount, basisValues) {
    const totalAmount = positiveComponentAmount(amount);
    if (!totalAmount || !basisValues.length) return basisValues.map(() => 0);

    const basisSum = basisValues.reduce((sum, value) => sum + Math.max(0, toNumber(value)), 0);
    const weights = basisSum > 0
      ? basisValues.map((value) => Math.max(0, toNumber(value)) / basisSum)
      : basisValues.map(() => 1 / basisValues.length);
    const allocations = weights.map((weight) => roundMoney(totalAmount * weight));
    const residual = roundMoney(totalAmount - allocations.reduce((sum, value) => sum + value, 0));
    if (Math.abs(residual) >= 0.01) {
      allocations[largestSourceTotalIndex(basisValues)] = roundMoney(allocations[largestSourceTotalIndex(basisValues)] + residual);
    }
    return allocations;
  }

  function largestSourceTotalIndex(values) {
    if (!values.length) return 0;
    let bestIndex = 0;
    let bestValue = Number.NEGATIVE_INFINITY;
    values.forEach((value, index) => {
      const number = toNumber(value);
      if (number > bestValue) {
        bestValue = number;
        bestIndex = index;
      }
    });
    return bestIndex;
  }

  function buildCombinedBulkInvoice(orders) {
    const normalizedOrders = orders.map(normalizeBulkInvoice);
    const orderDates = normalizedOrders.map((order) => order.orderDate).filter(Boolean).sort();
    const exactInvoiceDate = selectedBulkExactInvoiceDate();
    const generatedInvoiceDate = exactInvoiceDate || orderDates[orderDates.length - 1] || '';
    const orderNumbers = normalizedOrders.map((order) => order.orderNumber).filter(Boolean);
    const items = normalizedOrders.flatMap((order) => order.items.map((item) => ({
      ...item,
      sku: item.sku || (order.orderNumber ? `AE-${lastDigits(order.orderNumber, 8)}` : ''),
      description: `[${order.orderNumber || 'AliExpress'}] ${item.description || item.sku || 'Linea AliExpress'}`,
      sourceOrderNumber: order.orderNumber || '',
      sourceOrderDate: order.orderDate || '',
      sourceOrderUrl: order.pageUrl || '',
    })));
    const itemSubtotal = roundMoney(items.reduce((sum, item) => sum + sourceItemTotal(item), 0));
    const knownShipping = sumKnownTotals(normalizedOrders, 'shipping');
    const knownTax = sumKnownTotals(normalizedOrders, 'tax');
    const knownDiscount = sumKnownDiscounts(normalizedOrders);
    const orderGrandTotal = sumKnownTotals(normalizedOrders, 'total') || sumItems(items) || itemSubtotal;
    const finalItems = [...items];
    const combinedSubtotal = itemSubtotal;
    const finalTotal = orderGrandTotal;
    const notes = [
      `Factura consolidada desde ${normalizedOrders.length} orden(es) AliExpress.`,
      orderNumbers.length ? `Pedidos: ${orderNumbers.join(', ')}.` : '',
      'Shipping, tax y descuentos/coins fueron prorrateados por peso de cada producto dentro de su orden y convertidos a valores unitarios por cantidad.',
      exactInvoiceDate
        ? `Fecha de factura tomada del filtro Dia exacto: ${formatDateForStatus(exactInvoiceDate)}.`
        : `Rango: ${orderDates[0] || el.bulkFromDate.value || ''}${orderDates.length ? ` a ${orderDates[orderDates.length - 1]}` : ''}.`,
    ].filter(Boolean).join('\n');

    return {
      source: 'AliExpress',
      generatedAt: new Date().toISOString(),
      extractedAt: new Date().toISOString(),
      pageUrl: state.bulkMeta && state.bulkMeta.pageUrl || normalizedOrders[0]?.pageUrl || '',
      pageTitle: 'AliExpress bulk consolidated invoice',
      supplierName: 'AliExpress Marketplace',
      supplierTaxId: '',
      orderNumber: buildCombinedOrderNumber(orderNumbers),
      orderDate: generatedInvoiceDate,
      currency: 'CLP',
      subtotal: combinedSubtotal,
      shipping: knownShipping || null,
      tax: knownTax || null,
      discount: knownDiscount || null,
      total: finalTotal,
      notes,
      items: finalItems,
      warnings: normalizedOrders.flatMap((order) => order.warnings || []).concat(
        'Factura consolidada: las lineas incluyen el pedido origen entre corchetes.',
      ),
      sourceOrders: normalizedOrders.map((order) => ({
        orderNumber: order.orderNumber,
        orderDate: order.orderDate,
        total: order.total,
        subtotal: order.subtotal,
        shipping: order.shipping,
        tax: order.tax,
        discount: order.discount,
        pageUrl: order.pageUrl,
      })),
      bulkMath: {
        itemSubtotal,
        knownShipping,
        knownTax,
        knownDiscount,
        orderGrandTotal,
        finalTotal,
        allocatedRowTotal: sumItems(finalItems),
      },
    };
  }

  function sumKnownTotals(orders, field) {
    return roundMoney(orders.reduce((sum, order) => {
      const value = toNullableNumber(order[field]);
      return value === null ? sum : sum + value;
    }, 0));
  }

  function sumKnownDiscounts(orders) {
    return roundMoney(orders.reduce((sum, order) => {
      const value = toNullableNumber(order.discount);
      return value === null ? sum : sum + Math.abs(value);
    }, 0));
  }

  function buildCombinedOrderNumber(orderNumbers) {
    if (!orderNumbers.length) return `AE-BULK-${new Date().toISOString().slice(0, 10)}`;
    if (orderNumbers.length === 1) return orderNumbers[0];
    return `AE-BULK-${lastDigits(orderNumbers[0], 6)}-${lastDigits(orderNumbers[orderNumbers.length - 1], 6)}-${orderNumbers.length}`;
  }

  function selectedBulkExactInvoiceDate() {
    if (!el.bulkDateMode || el.bulkDateMode.value !== 'day') return '';
    return normalizeDateInputValue(el.bulkExactDate && el.bulkExactDate.value)
      || normalizeDateInputValue(el.bulkFromDate && el.bulkFromDate.value)
      || normalizeDateInputValue(el.bulkToDate && el.bulkToDate.value)
      || '';
  }

  function applyGeneratedInvoiceDate(invoice, exactInvoiceDate) {
    if (!exactInvoiceDate) return invoice;
    return {
      ...invoice,
      orderDate: exactInvoiceDate,
      notes: [
        invoice.notes || '',
        `Fecha de factura tomada del filtro Dia exacto: ${formatDateForStatus(exactInvoiceDate)}.`,
      ].filter(Boolean).join('\n'),
    };
  }

  function normalizeBulkInvoice(order) {
    const items = Array.isArray(order && order.items) ? order.items.map(normalizeItem).filter((item) => item.description || item.sku) : [];
    const total = toNumber(order && order.total) || sumItems(items);
    return allocateInvoiceComponents({
      source: 'AliExpress',
      generatedAt: new Date().toISOString(),
      extractedAt: order && order.extractedAt || new Date().toISOString(),
      pageUrl: order && order.pageUrl || '',
      pageTitle: order && order.pageTitle || '',
      supplierName: order && order.supplierName || 'AliExpress Marketplace',
      supplierTaxId: order && order.supplierTaxId || '',
      orderNumber: order && order.orderNumber || '',
      orderDate: order && order.orderDate || '',
      currency: 'CLP',
      subtotal: toNullableNumber(order && order.subtotal) || sumItems(items),
      shipping: toNullableNumber(order && order.shipping),
      tax: toNullableNumber(order && order.tax),
      discount: toNullableNumber(order && order.discount),
      total,
      notes: order && order.notes || '',
      items,
      warnings: order && order.warnings || [],
    });
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
    return allocateInvoiceComponents({
      source: 'AliExpress',
      generatedAt: new Date().toISOString(),
      extractedAt: state.extractedAt || '',
      pageUrl: state.pageUrl,
      pageTitle: state.pageTitle,
      supplierName: el.supplierName.value.trim() || 'AliExpress Marketplace',
      supplierTaxId: el.supplierTaxId.value.trim(),
      orderNumber: el.orderNumber.value.trim(),
      orderDate: el.orderDate.value || '',
      currency: 'CLP',
      subtotal: toNullableNumber(el.subtotal.value),
      shipping: toNullableNumber(el.shipping.value),
      tax: state.tax,
      discount: state.discount,
      total: toNumber(el.total.value),
      notes: el.notes.value.trim(),
      items: state.items.map(normalizeItem).filter((item) => item.description || item.sku),
      warnings: state.warnings,
    });
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
    // If the addon already AI-cleaned this row, keep that exact name and
    // don't run the heuristic cleaner over the original noisy title again.
    if (item.aiCleaned && item.description) {
      return {
        sku: String(item.sku || '').trim(),
        description: String(item.description).trim(),
        originalDescription: String(item.originalDescription || '').trim(),
        aiCleaned: true,
        aiCategory: String(item.aiCategory || '').trim(),
        aiBrand: String(item.aiBrand || '').trim(),
        aiModel: String(item.aiModel || '').trim(),
        aiComponent: String(item.aiComponent || '').trim(),
        aiConfidence: typeof item.aiConfidence === 'number' ? item.aiConfidence : null,
        quantity,
        unitPrice,
        total,
        sourceUnitPrice: toNullableNumber(item.sourceUnitPrice),
        sourceTotal: toNullableNumber(item.sourceTotal),
        allocatedDiscount: toNullableNumber(item.allocatedDiscount),
        allocatedDiscountTotal: toNullableNumber(item.allocatedDiscountTotal),
        allocatedShipping: toNullableNumber(item.allocatedShipping),
        allocatedShippingTotal: toNullableNumber(item.allocatedShippingTotal),
        allocatedTax: toNullableNumber(item.allocatedTax),
        allocatedTaxTotal: toNullableNumber(item.allocatedTaxTotal),
        allocationGranularity: item.allocationGranularity || '',
        productUrl: item.productUrl || '',
        itemId: item.itemId || '',
        imageUrl: item.imageUrl || '',
      };
    }
    const sourceDescription = String(item.originalDescription || item.description || '').trim();
    const cleanedDescription = smartProductName(sourceDescription, item);
    const currentDescription = cleanVisibleProductName(item.description);
    const description = cleanedDescription || currentDescription;
    const originalDescription = sourceDescription && sourceDescription !== description
      ? sourceDescription
      : String(item.originalDescription || '').trim();
    return {
      sku: String(item.sku || '').trim(),
      description,
      originalDescription,
      quantity,
      unitPrice,
      total,
      sourceUnitPrice: toNullableNumber(item.sourceUnitPrice),
      sourceTotal: toNullableNumber(item.sourceTotal),
      allocatedDiscount: toNullableNumber(item.allocatedDiscount),
      allocatedDiscountTotal: toNullableNumber(item.allocatedDiscountTotal),
      allocatedShipping: toNullableNumber(item.allocatedShipping),
      allocatedShippingTotal: toNullableNumber(item.allocatedShippingTotal),
      allocatedTax: toNullableNumber(item.allocatedTax),
      allocatedTaxTotal: toNullableNumber(item.allocatedTaxTotal),
      allocationGranularity: item.allocationGranularity || '',
      productUrl: item.productUrl || '',
      itemId: item.itemId || '',
      imageUrl: item.imageUrl || '',
    };
  }

  function smartProductName(description, item = {}) {
    const raw = String(description || '').replace(/\s+/g, ' ').trim();
    if (!raw) return '';

    const base = stripAliExpressTitleNoise(raw);
    const normalized = normalizeNameKey(base);
    const brand = extractCatalogBrand(base);
    const variant = extractTrailingVariant(base);

    if (isBottomBracketTitle(normalized)) {
      return compactName([
        'Motor sellado',
        brand,
        bottomBracketSizeLabel(base),
        bottomBracketStandardLabel(base),
      ]);
    }

    if (isFrontLightTitle(normalized)) {
      return compactName([
        'Luz delantera',
        brand,
        extractLightEmitterLabel(base),
        usbTypeCLabel(normalized),
        variant,
      ]);
    }

    if (isRearLightTitle(normalized)) {
      return compactName([
        'Luz trasera',
        brand,
        /\bled\b/i.test(base) ? 'LED' : '',
        usbTypeCLabel(normalized),
        variant,
      ]);
    }

    return compactGenericProductName(base, variant, item);
  }

  function stripAliExpressTitleNoise(value) {
    return String(value || '')
      .replace(/^\s*\[\d{8,}\]\s*/, '')
      .replace(/\s*\bItem\s*ID\s*:?\s*\d{8,}\b/gi, '')
      .replace(/\s*\bORIGINAL_TITLE\s*:.*$/i, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function cleanVisibleProductName(value) {
    return stripAliExpressTitleNoise(value)
      .replace(/\s*\bPRODUCT_URL\s*:.*$/i, '')
      .replace(/\s*\bIMAGE_URL\s*:.*$/i, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function normalizeNameKey(value) {
    return String(value || '')
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function extractTrailingVariant(value) {
    const match = String(value || '').match(/\(([^()]{2,50})\)\s*$/);
    if (!match) return '';
    const variant = match[1].replace(/\s+/g, ' ').trim();
    if (/^\d{8,}$/.test(variant)) return '';
    return variant;
  }

  function extractCatalogBrand(value) {
    const knownBrands = [
      'ZTTO', 'Shimano', 'SRAM', 'KMC', 'Rockbros', 'Wake', 'GUB', 'Litepro',
      'Bolany', 'Zoom', 'Tektro', 'Magura', 'Ltwoo', 'Sensah', 'YBN', 'Sunrace',
      'Maxxis', 'Kenda', 'Continental', 'Vittoria', 'Schwalbe', 'Prowheel',
      'MZYRH', 'Bafang', 'RISK', 'TOSEEK', 'UNO', 'Meroca', 'Bucklos', 'CST',
    ];
    const text = String(value || '');
    for (const brand of knownBrands) {
      if (new RegExp(`\\b${escapeRegExp(brand)}\\b`, 'i').test(text)) return brand;
    }
    const acronym = text.match(/\b[A-Z][A-Z0-9]{2,8}\b/);
    if (!acronym) return '';
    const blocked = new Set(['USB', 'LED', 'BSA', 'ISO', 'JIS', 'MTB', 'BMX', 'BB', 'T6']);
    if (blocked.has(acronym[0]) || /^[A-Z]{1,4}\d{1,5}$/.test(acronym[0])) return '';
    return acronym[0];
  }

  function isBottomBracketTitle(normalized) {
    return /\b(soporte inferior|bottom bracket|movimiento central|pedalier|caja de motor|eje de motor|motor sellado|bsa \d{2}|bb iso|bb jis|hollowtech|pressfit|bb30|pf30|square taper)\b/.test(normalized);
  }

  function bottomBracketSizeLabel(value) {
    const text = String(value || '').replace(/,/g, '.');
    const sizeMatch = text.match(/\b(\d{2,3})\s*[xX×]\s*(\d{2,3}(?:\.\d+)?)\s*L?\b/);
    if (sizeMatch) return `BSA ${sizeMatch[1]}X${trimDecimal(sizeMatch[2])}`;
    const bsaMatch = text.match(/\bBSA\s*(\d{2,3})\b/i);
    return bsaMatch ? `BSA ${bsaMatch[1]}` : '';
  }

  function bottomBracketStandardLabel(value) {
    const text = String(value || '');
    if (/\bBB\s*ISO\b|\bISO\b/i.test(text)) return 'ISO';
    if (/\bJIS\b/i.test(text)) return 'JIS';
    return '';
  }

  function isFrontLightTitle(normalized) {
    return /\b(luz delantera|faro|front light|headlight)\b/.test(normalized);
  }

  function isRearLightTitle(normalized) {
    return /\b(luz trasera|lampara trasera|rear light|tail light)\b/.test(normalized);
  }

  function extractLightEmitterLabel(value) {
    const match = String(value || '').match(/\b(\d+)\s*T6\b/i) || String(value || '').match(/\bT6\b/i);
    if (!match) return '';
    return 'T6';
  }

  function usbTypeCLabel(normalized) {
    return /\b(usb c|usb tipo c|tipo c|type c|carga tipo c)\b/.test(normalized) ? 'USB C' : '';
  }

  function compactGenericProductName(base, variant, item) {
    const withoutVariant = String(base || '').replace(/\s*\([^()]{2,50}\)\s*$/, '');
    const cleaned = withoutVariant
      .replace(/\b(de|para)\s+bicicleta\b/gi, '')
      .replace(/\bbicicleta\b/gi, '')
      .replace(/\b(montana|montaña|carretera|ciclismo nocturno|conduccion nocturna|conducción nocturna|accesorios? de seguridad)\b/gi, '')
      .replace(/[,;]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    const words = cleaned.split(/\s+/).filter(Boolean).slice(0, 9).join(' ');
    const fallback = words || String(item && item.sku || '').trim() || base;
    return compactName([sentenceCaseProductName(fallback), variant]);
  }

  function sentenceCaseProductName(value) {
    const text = String(value || '').trim();
    if (!text) return '';
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  function compactName(parts) {
    const seen = new Set();
    return parts
      .map((part) => String(part || '').replace(/\s+/g, ' ').trim())
      .filter(Boolean)
      .filter((part) => {
        const key = normalizeNameKey(part);
        if (!key || seen.has(key)) return false;
        seen.add(key);
        return true;
      })
      .join(' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function trimDecimal(value) {
    return String(value || '').replace(/\.0+$/, '').replace(/(\.\d*?)0+$/, '$1');
  }

  function escapeRegExp(value) {
    return String(value || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
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
    if (!el.orderDate.value) el.orderDate.value = todayIso();
  }

  function setDefaultBulkDates() {
    const today = new Date();
    const from = new Date(today);
    from.setDate(from.getDate() - clampInteger(state.settings.rangeDays, 1, 365, DEFAULT_SETTINGS.rangeDays));
    if (el.bulkDateMode && !el.bulkDateMode.value) el.bulkDateMode.value = state.settings.defaultDateMode;
    if (el.bulkDateMode) el.bulkDateMode.value = state.settings.defaultDateMode;
    if (el.bulkOutputMode) el.bulkOutputMode.value = state.settings.defaultOutputMode;
    if (el.bulkToDate && !el.bulkToDate.value) el.bulkToDate.value = todayIso(today);
    if (el.bulkFromDate && !el.bulkFromDate.value) el.bulkFromDate.value = todayIso(from);
    if (el.bulkExactDate && !el.bulkExactDate.value) el.bulkExactDate.value = el.bulkToDate.value || todayIso(today);
  }

  async function loadSettings() {
    try {
      const stored = await chrome.storage.local.get(SETTINGS_STORAGE);
      state.settings = sanitizeSettings(stored && stored[SETTINGS_STORAGE]);
    } catch (_error) {
      state.settings = { ...DEFAULT_SETTINGS };
    }
    renderSettings();
  }

  function renderSettings() {
    if (!el.settingsDefaultDateMode) return;
    el.settingsDefaultDateMode.value = state.settings.defaultDateMode;
    el.settingsRangeDays.value = String(state.settings.rangeDays);
    el.settingsDefaultOutputMode.value = state.settings.defaultOutputMode;
    el.settingsMaxSeparateInvoices.value = String(state.settings.maxSeparateInvoices);
    el.settingsAutoSelectOrders.checked = state.settings.autoSelectCollectedOrders;
    el.settingsEnrichDetails.checked = state.settings.enrichDetailsBeforeOutput;
  }

  async function saveSettings({ applyNow }) {
    state.settings = readSettingsFromControls();
    await chrome.storage.local.set({ [SETTINGS_STORAGE]: state.settings });
    renderSettings();
    if (applyNow) {
      applySettingsToCurrentBulkRun();
      setStatus('Ajustes guardados y aplicados a esta colecta. Vuelve a colectar para refrescar la lista.', 'success');
    } else {
      setStatus('Ajustes guardados. Se usaran como default en el panel.', 'success');
    }
  }

  async function resetSettings() {
    state.settings = { ...DEFAULT_SETTINGS };
    await chrome.storage.local.set({ [SETTINGS_STORAGE]: state.settings });
    renderSettings();
    applySettingsToCurrentBulkRun();
    setStatus('Ajustes restaurados y aplicados.', 'success');
  }

  function applySettingsToCurrentBulkRun() {
    const today = new Date();
    const from = new Date(today);
    from.setDate(from.getDate() - clampInteger(state.settings.rangeDays, 1, 365, DEFAULT_SETTINGS.rangeDays));
    el.bulkDateMode.value = state.settings.defaultDateMode;
    el.bulkFromDate.value = todayIso(from);
    el.bulkToDate.value = todayIso(today);
    el.bulkExactDate.value = todayIso(today);
    el.bulkOutputMode.value = state.settings.defaultOutputMode;
    syncBulkDateModeUi({ syncInputs: true });
    state.bulkOrders = [];
    state.bulkMeta = null;
    state.bulkSelection = null;
    setBulkProgress({ active: false, label: 'Listo', detail: 'Ajustes aplicados. Colecta nuevamente.', percent: 0, type: 'neutral' });
    renderBulkOrders();
    saveBulkWorkspaceState('Ajustes aplicados. Colecta nuevamente.', 'neutral');
  }

  function readSettingsFromControls() {
    return sanitizeSettings({
      defaultDateMode: el.settingsDefaultDateMode.value,
      rangeDays: el.settingsRangeDays.value,
      defaultOutputMode: el.settingsDefaultOutputMode.value,
      maxSeparateInvoices: el.settingsMaxSeparateInvoices.value,
      autoSelectCollectedOrders: el.settingsAutoSelectOrders.checked,
      enrichDetailsBeforeOutput: el.settingsEnrichDetails.checked,
    });
  }

  function sanitizeSettings(settings) {
    const value = settings && typeof settings === 'object' ? settings : {};
    return {
      defaultDateMode: value.defaultDateMode === 'day' ? 'day' : 'range',
      rangeDays: clampInteger(value.rangeDays, 1, 365, DEFAULT_SETTINGS.rangeDays),
      defaultOutputMode: value.defaultOutputMode === 'combined' ? 'combined' : 'separate',
      autoSelectCollectedOrders: value.autoSelectCollectedOrders !== false,
      enrichDetailsBeforeOutput: value.enrichDetailsBeforeOutput !== false,
      maxSeparateInvoices: clampInteger(value.maxSeparateInvoices, 1, 50, DEFAULT_SETTINGS.maxSeparateInvoices),
    };
  }

  function clampInteger(value, min, max, fallback) {
    const number = Number.parseInt(String(value), 10);
    if (!Number.isFinite(number)) return fallback;
    return Math.max(min, Math.min(max, number));
  }

  function todayIso(date = new Date()) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  function syncBulkDateModeUi({ syncInputs = false } = {}) {
    if (!el.bulkDateMode) return;
    const isDay = el.bulkDateMode.value === 'day';
    el.bulkExactDateField.classList.toggle('visible', isDay);
    el.bulkRangeFields.classList.toggle('hidden', isDay);
    if (isDay && !el.bulkExactDate.value) {
      el.bulkExactDate.value = el.bulkFromDate.value || el.bulkToDate.value || todayIso();
    }
    if (syncInputs && isDay && el.bulkExactDate.value) {
      el.bulkFromDate.value = el.bulkExactDate.value;
      el.bulkToDate.value = el.bulkExactDate.value;
    }
  }

  function getBulkDateFilters({ syncInputs = false } = {}) {
    const mode = el.bulkDateMode && el.bulkDateMode.value === 'day' ? 'day' : 'range';
    let exactDate = normalizeDateInputValue(el.bulkExactDate && el.bulkExactDate.value);
    let fromDate = normalizeDateInputValue(el.bulkFromDate && el.bulkFromDate.value);
    let toDate = normalizeDateInputValue(el.bulkToDate && el.bulkToDate.value);

    if (mode === 'day') {
      exactDate = exactDate || fromDate || toDate || todayIso();
      fromDate = exactDate;
      toDate = exactDate;
      if (syncInputs) {
        el.bulkExactDate.value = exactDate;
        el.bulkFromDate.value = exactDate;
        el.bulkToDate.value = exactDate;
      }
      return {
        dateMode: 'day',
        exactDate,
        fromDate,
        toDate,
        label: `Dia exacto ${formatDateForStatus(exactDate)}`,
      };
    }

    if (fromDate && toDate && fromDate > toDate) {
      const originalFrom = fromDate;
      fromDate = toDate;
      toDate = originalFrom;
    }
    if (syncInputs) {
      if (fromDate) el.bulkFromDate.value = fromDate;
      if (toDate) el.bulkToDate.value = toDate;
    }

    return {
      dateMode: 'range',
      exactDate: '',
      fromDate,
      toDate,
      label: `Rango ${formatDateForStatus(fromDate) || 'sin inicio'} a ${formatDateForStatus(toDate) || 'sin fin'}`,
    };
  }

  function normalizeDateInputValue(value) {
    const text = String(value || '').trim();
    if (!text) return '';
    let match = text.match(/^(20\d{2})-(\d{2})-(\d{2})$/);
    if (match) return text;
    match = text.match(/^(\d{1,2})[/-](\d{1,2})[/-](20\d{2}|\d{2})$/);
    if (match) {
      const year = Number(match[3]) < 100 ? 2000 + Number(match[3]) : Number(match[3]);
      return `${String(year).padStart(4, '0')}-${String(Number(match[2])).padStart(2, '0')}-${String(Number(match[1])).padStart(2, '0')}`;
    }
    return '';
  }

  function formatDateForStatus(isoDate) {
    const value = normalizeDateInputValue(isoDate);
    if (!value) return '';
    const [year, month, day] = value.split('-');
    return `${day}/${month}/${year}`;
  }

  function setBulkProgress(progress) {
    state.bulkProgress = {
      active: Boolean(progress && progress.active),
      label: progress && progress.label || 'Listo',
      detail: progress && progress.detail || '',
      current: Number(progress && progress.current) || 0,
      total: Number(progress && progress.total) || 0,
      percent: Number.isFinite(Number(progress && progress.percent)) ? Number(progress.percent) : null,
      type: progress && progress.type || 'neutral',
    };
    renderBulkProgress();
  }

  function renderBulkProgress(progress = state.bulkProgress) {
    if (!el.bulkProgress) return;
    const currentProgress = progress || {
      active: false,
      label: 'Listo',
      detail: 'Sin proceso bulk activo.',
      current: 0,
      total: 0,
      percent: 0,
      type: 'idle',
    };
    const percent = Math.max(0, Math.min(100, currentProgress.percent !== null && currentProgress.percent !== undefined
      ? Number(currentProgress.percent)
      : (currentProgress.total ? (Number(currentProgress.current) / Number(currentProgress.total)) * 100 : 0)));
    const typeClass = currentProgress.type === 'success' || currentProgress.type === 'error' || currentProgress.type === 'warning'
      ? currentProgress.type
      : (currentProgress.active ? 'active' : 'idle');
    el.bulkProgress.className = `bulk-progress ${typeClass}`;
    el.bulkProgressLabel.textContent = currentProgress.label || 'Listo';
    el.bulkProgressCount.textContent = currentProgress.total
      ? `${Math.min(Number(currentProgress.current) || 0, Number(currentProgress.total))}/${currentProgress.total}`
      : `${Math.round(percent)}%`;
    el.bulkProgressBar.style.width = `${percent}%`;
    el.bulkProgressDetail.textContent = currentProgress.detail || 'Sin proceso bulk activo.';
  }

  function workspaceParams() {
    return new URLSearchParams(location.search || '');
  }

  function isWorkspaceMode() {
    return workspaceParams().get('workspace') === '1' || document.body.dataset.workspace === '1';
  }

  function applyWorkspaceUrlParams() {
    const params = workspaceParams();
    if (params.get('from')) el.bulkFromDate.value = params.get('from');
    if (params.get('to')) el.bulkToDate.value = params.get('to');
    if (params.get('dateMode') && el.bulkDateMode) el.bulkDateMode.value = params.get('dateMode');
    if (params.get('exactDate') && el.bulkExactDate) el.bulkExactDate.value = params.get('exactDate');
    if (params.get('mode') && el.bulkOutputMode) el.bulkOutputMode.value = params.get('mode');
    if (isWorkspaceMode()) {
      document.body.classList.add('workspace-mode');
      if (el.openWorkspaceButton) el.openWorkspaceButton.hidden = true;
      if (el.collectBulkButton) el.collectBulkButton.textContent = 'Colectar';
      if (params.get('autocollect') === '1') {
        window.setTimeout(() => collectBulkOrders(), 250);
      }
    } else {
      if (el.openWorkspaceButton) el.openWorkspaceButton.textContent = 'Abrir panel estable';
      if (el.collectBulkButton) el.collectBulkButton.textContent = 'Abrir panel y colectar';
    }
  }

  async function openBulkWorkspace({ autocollect }) {
    try {
      const sourceTab = await getAliExpressSourceTab();
      const filters = getBulkDateFilters({ syncInputs: true });
      state.bulkSourceTabId = sourceTab.id;
      await saveBulkWorkspaceState('Abriendo panel lateral bulk...', 'neutral', {
        sourceTabId: sourceTab.id,
        pendingAutocollect: Boolean(autocollect),
      });

      if (chrome.sidePanel && chrome.sidePanel.open) {
        try {
          if (chrome.sidePanel.setOptions) {
            await chrome.sidePanel.setOptions({ path: 'sidepanel.html', enabled: true });
          }
          await chrome.sidePanel.open({ windowId: sourceTab.windowId });
          setStatus('Panel lateral bulk abierto. Puedes seguir navegando sin perder el progreso.', 'success');
          closeTransientPopupSoon();
          return;
        } catch (sidePanelError) {
          await saveBulkWorkspaceState(`No se pudo abrir panel lateral (${sidePanelError.message || String(sidePanelError)}). Usando pestana estable.`, 'warning', {
            sourceTabId: sourceTab.id,
            pendingAutocollect: Boolean(autocollect),
          });
        }
      }

      const params = new URLSearchParams({
        workspace: '1',
        sourceTab: String(sourceTab.id),
        dateMode: filters.dateMode,
        exactDate: filters.exactDate || '',
        from: filters.fromDate || '',
        to: filters.toDate || '',
        mode: el.bulkOutputMode ? el.bulkOutputMode.value : 'separate',
      });
      await chrome.tabs.create({ url: chrome.runtime.getURL(`sidepanel.html?${params.toString()}`), active: true });
      closeTransientPopupSoon();
    } catch (error) {
      setStatus(error.message || String(error), 'error');
    }
  }

  function closeTransientPopupSoon() {
    if (isWorkspaceMode()) return;
    window.setTimeout(() => {
      try { window.close(); } catch (_) { /* Chrome may ignore close outside action popup. */ }
    }, 120);
  }

  async function getAliExpressSourceTab() {
    const params = workspaceParams();
    const sourceTabId = Number(params.get('sourceTab') || 0);
    if (sourceTabId) {
      try {
        const tab = await chrome.tabs.get(sourceTabId);
        if (tab && /^https:\/\/([^/]+\.)?aliexpress\.com\//i.test(tab.url || '')) return tab;
      } catch (_) {
        // Fall back to active tab below.
      }
    }
    if (state.bulkSourceTabId) {
      try {
        const tab = await chrome.tabs.get(state.bulkSourceTabId);
        if (tab && /^https:\/\/([^/]+\.)?aliexpress\.com\//i.test(tab.url || '')) return tab;
      } catch (_) {
        // Fall back to active tab below.
      }
    }

    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    const activeTab = tabs && tabs[0];
    if (activeTab && /^https:\/\/([^/]+\.)?aliexpress\.com\//i.test(activeTab.url || '')) return activeTab;
    const aliTabs = await chrome.tabs.query({ url: ['https://*.aliexpress.com/*', 'https://aliexpress.com/*'] });
    if (aliTabs && aliTabs.length) return aliTabs[0];
    throw new Error('No encontre una pestana de AliExpress abierta para usar como origen.');
  }

  async function restoreBulkWorkspaceState() {
    try {
      const stored = await chrome.storage.local.get(BULK_WORKSPACE_STORAGE);
      const snapshot = stored && stored[BULK_WORKSPACE_STORAGE];
      if (snapshot) {
        const hasStoredOrders = Array.isArray(snapshot.bulkOrders) && snapshot.bulkOrders.length > 0;
        const shouldRestoreBulkInputs = hasStoredOrders || snapshot.pendingAutocollect;
        if (shouldRestoreBulkInputs && snapshot.dateMode && el.bulkDateMode && !workspaceParams().get('dateMode')) el.bulkDateMode.value = snapshot.dateMode;
        if (shouldRestoreBulkInputs && snapshot.exactDate && !workspaceParams().get('exactDate')) el.bulkExactDate.value = snapshot.exactDate;
        if (shouldRestoreBulkInputs && snapshot.fromDate && !workspaceParams().get('from')) el.bulkFromDate.value = snapshot.fromDate;
        if (shouldRestoreBulkInputs && snapshot.toDate && !workspaceParams().get('to')) el.bulkToDate.value = snapshot.toDate;
        syncBulkDateModeUi();
        if (shouldRestoreBulkInputs && snapshot.outputMode && el.bulkOutputMode && !workspaceParams().get('mode')) el.bulkOutputMode.value = snapshot.outputMode;
        state.bulkMeta = snapshot.bulkMeta || state.bulkMeta;
        state.bulkOrders = Array.isArray(snapshot.bulkOrders) ? snapshot.bulkOrders.map(normalizeBulkInvoice) : state.bulkOrders;
        state.bulkSelection = Array.isArray(snapshot.bulkSelection) ? snapshot.bulkSelection : state.bulkSelection;
        state.bulkSourceTabId = snapshot.sourceTabId || state.bulkSourceTabId;
        state.bulkProgress = snapshot.bulkProgress || state.bulkProgress;
        renderBulkProgress();
        if (snapshot.statusMessage) setStatus(snapshot.statusMessage, snapshot.statusType || 'neutral');
        if (isWorkspaceMode() && snapshot.pendingAutocollect) {
          await chrome.storage.local.set({
            [BULK_WORKSPACE_STORAGE]: { ...snapshot, pendingAutocollect: false },
          });
          window.setTimeout(() => collectBulkOrders(), 250);
        }
      }
    } catch (_) {
      // Local restore is convenience only; extraction still works without it.
    }
    renderBulkOrders();
  }

  function setupBulkWorkspaceStorageListener() {
    if (!isWorkspaceMode() || !chrome.storage || !chrome.storage.onChanged) return;
    chrome.storage.onChanged.addListener((changes, areaName) => {
      if (areaName !== 'local' || !changes[BULK_WORKSPACE_STORAGE]) return;
      const snapshot = changes[BULK_WORKSPACE_STORAGE].newValue;
      if (!snapshot) return;
      applyBulkWorkspaceSnapshot(snapshot);
      if (!snapshot.pendingAutocollect) return;
      chrome.storage.local.set({
        [BULK_WORKSPACE_STORAGE]: { ...snapshot, pendingAutocollect: false },
      }).then(() => {
        setStatus('Solicitud recibida desde el popup. Colectando en este panel...', 'neutral');
        window.setTimeout(() => collectBulkOrders(), 150);
      });
    });
  }

  function applyBulkWorkspaceSnapshot(snapshot) {
    if (!snapshot) return;
    if (snapshot.dateMode && el.bulkDateMode) el.bulkDateMode.value = snapshot.dateMode;
    if (snapshot.exactDate && el.bulkExactDate) el.bulkExactDate.value = snapshot.exactDate;
    if (snapshot.fromDate && el.bulkFromDate) el.bulkFromDate.value = snapshot.fromDate;
    if (snapshot.toDate && el.bulkToDate) el.bulkToDate.value = snapshot.toDate;
    if (snapshot.outputMode && el.bulkOutputMode) el.bulkOutputMode.value = snapshot.outputMode;
    state.bulkSourceTabId = snapshot.sourceTabId || state.bulkSourceTabId;
    syncBulkDateModeUi();
  }

  async function saveBulkWorkspaceState(statusMessage, statusType, extra = {}) {
    const selection = Array.from(el.bulkOrdersList.querySelectorAll('[data-bulk-check]:checked'))
      .map((input) => state.bulkOrders[Number(input.dataset.bulkCheck)])
      .filter(Boolean)
      .map(bulkOrderSelectionKey)
      .filter(Boolean);
    if (selection.length || state.bulkOrders.length) state.bulkSelection = selection;

    const filters = getBulkDateFilters();
    const snapshot = {
      updatedAt: new Date().toISOString(),
      dateMode: filters.dateMode,
      exactDate: filters.exactDate || '',
      fromDate: filters.fromDate || '',
      toDate: filters.toDate || '',
      outputMode: el.bulkOutputMode ? el.bulkOutputMode.value : 'separate',
      bulkMeta: state.bulkMeta,
      bulkOrders: state.bulkOrders.map(normalizeBulkInvoice),
      bulkSelection: state.bulkSelection || [],
      bulkProgress: state.bulkProgress,
      sourceTabId: extra.sourceTabId || state.bulkSourceTabId || null,
      pendingAutocollect: Boolean(extra.pendingAutocollect),
      statusMessage: statusMessage || el.status.textContent || '',
      statusType: statusType || Array.from(el.status.classList).find((name) => name !== 'status') || 'neutral',
    };
    await chrome.storage.local.set({ [BULK_WORKSPACE_STORAGE]: snapshot });
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

  function lastDigits(value, length) {
    return String(value || '').replace(/\D+/g, '').slice(-length) || String(value || '').slice(-length);
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
