(function () {
  'use strict';

  const STORAGE_PREFIX = 'aliexpressInvoiceDraft:';
  const hasDocument = typeof document !== 'undefined';
  const root = hasDocument ? document.getElementById('invoiceRoot') : null;
  const toolbarMeta = hasDocument ? document.getElementById('toolbarMeta') : null;
  let currentInvoice = null;

  if (hasDocument) {
    document.getElementById('printButton')?.addEventListener('click', () => window.print());
    document.getElementById('downloadHtmlButton')?.addEventListener('click', downloadHtml);
    document.getElementById('downloadJsonButton')?.addEventListener('click', downloadJson);
    document.getElementById('copyTextButton')?.addEventListener('click', copyOcrText);
    loadInvoice();
  }

  async function loadInvoice() {
    const embeddedInvoice = globalThis.__ALIEXPRESS_INVOICE_DATA__;
    if (embeddedInvoice && typeof embeddedInvoice === 'object') {
      currentInvoice = normalizeInvoice(embeddedInvoice);
      document.title = `AliExpress ${currentInvoice.orderNumber || 'invoice'}`;
      if (toolbarMeta) {
        toolbarMeta.textContent = currentInvoice.orderNumber
          ? `Pedido ${currentInvoice.orderNumber}`
          : '';
      }
      renderInvoice(currentInvoice);
      globalThis.__ALIEXPRESS_INVOICE_READY__ = true;
      return;
    }

    const params = new URLSearchParams(location.search);
    const draftId = params.get('draft');

    if (!draftId) {
      renderError('No se encontro el borrador de factura. Vuelve al popup y genera el documento otra vez.');
      return;
    }

    const key = `${STORAGE_PREFIX}${draftId}`;
    const data = await chrome.storage.local.get(key);
    const invoice = data[key];

    if (!invoice) {
      renderError('El borrador expiro o fue eliminado. Vuelve al popup y genera el documento otra vez.');
      return;
    }

    currentInvoice = normalizeInvoice(invoice);
    document.title = `AliExpress ${currentInvoice.orderNumber || 'invoice'}`;
    if (toolbarMeta) {
      toolbarMeta.textContent = currentInvoice.orderNumber ? `Pedido ${currentInvoice.orderNumber}` : '';
    }
    renderInvoice(currentInvoice);
    globalThis.__ALIEXPRESS_INVOICE_READY__ = true;
  }

  function renderInvoice(invoice) {
    if (!root) return;
    root.innerHTML = buildInvoiceMarkup(invoice);
    wireImageFallbacks();
  }

  function buildInvoiceMarkup(invoice) {
    const itemRows = invoice.items.map((item, index) => `
      <tr>
        <td class="index-cell">${index + 1}</td>
        <td class="image-cell">
          ${(item.embeddedImageUrl || item.imageUrl) ? `<img class="item-image" src="${escapeAttr(item.embeddedImageUrl || item.imageUrl)}" alt="" referrerpolicy="no-referrer">` : '<div class="item-image-empty"></div>'}
        </td>
        <td>
          <div class="article-copy">
            <strong>${escapeHtml(item.description || 'AliExpress item')}</strong>
            <div class="muted">SKU: ${escapeHtml(item.sku || 'AE-ITEM')}</div>
            ${item.unitsPerPurchase > 1 ? `<div class="muted">Compra AliExpress: ${formatQuantity(item.sourcePurchaseQuantity)} × ${formatQuantity(item.unitsPerPurchase)} pares = ${formatQuantity(item.quantity)} pares</div>` : ''}
            <span class="machine-metadata">${buildMachineMetadata(item)}</span>
          </div>
        </td>
        <td class="numeric">${formatQuantity(item.quantity)}</td>
        <td class="numeric">${formatUnitMoney(item.sourceUnitPrice ?? item.unitPrice, invoice.currency)}</td>
        <td class="numeric allocation-cell">${formatOptionalUnitMoney(-Math.abs(toNumber(item.allocatedDiscount)), invoice.currency)}</td>
        <td class="numeric allocation-cell">${formatOptionalUnitMoney(item.allocatedShipping, invoice.currency)}</td>
        <td class="numeric allocation-cell">${formatOptionalUnitMoney(item.allocatedTax, invoice.currency)}</td>
        <td class="numeric allocation-cell">${formatOptionalUnitMoney(item.allocatedAdjustment, invoice.currency)}</td>
        <td class="numeric calculated-cost-cell">${formatUnitMoney(item.unitPrice, invoice.currency)}</td>
        <td class="numeric">${formatMoney(item.total, invoice.currency)}</td>
      </tr>
    `).join('');

    const itemSubtotal = sumItems(invoice.items);
    const sourceSubtotal = invoice.subtotal || sumSourceItems(invoice.items) || itemSubtotal;
    const shipping = toNumber(invoice.shipping);
    const adjustment = toNullableNumber(invoice.componentDifference)
      ?? roundMoney(invoice.items.reduce(
        (sum, item) => sum + toNumber(item.allocatedAdjustmentTotal),
        0,
      ));
    const paidAmount = invoice.total;
    const balance = Math.max(0, roundMoney(invoice.total - paidAmount));
    const logoUrl = String(
      globalThis.__ALIEXPRESS_INVOICE_LOGO_URL__
        || 'https://vinabike.cl/vinabike-logo.png',
    );
    const machineInvoice = {
      ...invoice,
      items: invoice.items.map(({ embeddedImageUrl, ...item }) => item),
    };

    return `
      <header class="invoice-header">
        <div class="brand-mark">
          <img class="brand-logo" src="${escapeAttr(logoUrl)}" alt="Vinabike">
        </div>
        <aside class="invoice-summary">
          <strong># ${escapeHtml(invoice.orderNumber)}</strong>
          <span>Saldo adeudado</span>
          <b>${formatMoney(balance, invoice.currency)}</b>
        </aside>
      </header>

      <section class="company-info">
        <div>Viñabike</div>
        <div>Valparaíso</div>
        <div>Chile</div>
      </section>

      <section class="party-row">
        <div>
          <div class="label">Proveedor</div>
          <div class="supplier-name">${escapeHtml(invoice.supplierName)}</div>
          ${invoice.supplierTaxId ? `<div class="muted">${escapeHtml(invoice.supplierTaxId)}</div>` : ''}
        </div>
        <div class="date-box">
          <div class="muted">Fecha de la factura :</div>
          <div>${formatDate(invoice.orderDate)}</div>
        </div>
      </section>

      <section class="section">
        <table class="items-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Imagen</th>
              <th>Artículo &amp; Descripción</th>
              <th class="numeric">Cantidad</th>
              <th class="numeric">Tarifa origen</th>
              <th class="numeric">Desc./coins u.</th>
              <th class="numeric">Envío u.</th>
              <th class="numeric">Tax u.</th>
              <th class="numeric">Ajuste u.</th>
              <th class="numeric">Costo unit. calc.</th>
              <th class="numeric">Importe</th>
            </tr>
          </thead>
          <tbody>${itemRows}</tbody>
        </table>
      </section>

      <section class="section totals">
        <div class="totals-row"><span>Subtotal productos</span><span>${formatMoney(sourceSubtotal, invoice.currency)}</span></div>
        ${invoice.discount ? `<div class="totals-row"><span>Descuento / coins</span><span>${formatMoney(-Math.abs(invoice.discount), invoice.currency)}</span></div>` : ''}
        ${shipping > 0 ? `<div class="totals-row"><span>Shipping</span><span>${formatMoney(shipping, invoice.currency)}</span></div>` : ''}
        <div class="totals-row subtotal-row"><span>Neto (subtotal imponible)</span><span>${formatMoney(sourceSubtotal - Math.abs(invoice.discount || 0) + shipping, invoice.currency)}</span></div>
        ${invoice.tax ? `<div class="totals-row"><span>IVA / Tax</span><span>${formatMoney(invoice.tax, invoice.currency)}</span></div>` : ''}
        ${adjustment ? `<div class="totals-row"><span>Ajuste AliExpress / redondeo</span><span>${formatMoney(adjustment, invoice.currency)}</span></div>` : ''}
        <div class="totals-row grand-total"><span>TOTAL</span><span>${formatMoney(invoice.total, invoice.currency)}</span></div>
        <div class="totals-row paid-row"><span>Pago realizado</span><span>${formatMoney(paidAmount, invoice.currency)}</span></div>
        <div class="totals-row balance-row"><span>Saldo adeudado</span><span>${formatMoney(balance, invoice.currency)}</span></div>
      </section>

      <script type="application/json" id="aliexpress-invoice-data">${escapeHtml(JSON.stringify(machineInvoice))}</script>
    `;
  }

  function wireImageFallbacks() {
    root.querySelectorAll('.item-image').forEach((image) => {
      image.addEventListener('error', () => image.remove(), { once: true });
    });

    const logo = root.querySelector('.brand-logo');
    if (logo) {
      logo.addEventListener('error', () => {
        const fallback = document.createElement('strong');
        fallback.textContent = 'VINABIKE';
        logo.replaceWith(fallback);
      }, { once: true });
    }
  }

  function buildOcrText(invoice) {
    const lines = [
      'FACTURA DE COMPRA',
      invoice.supplierName,
    ];

    if (invoice.supplierTaxId) lines.push(`RUT: ${invoice.supplierTaxId}`);
    lines.push(`Pedido # ${invoice.orderNumber}`);
    lines.push(`Factura ${invoice.orderNumber}`);
    lines.push(`Fecha: ${formatDate(invoice.orderDate)}`);
    lines.push('SKU DESCRIPCION CANTIDAD TARIFA_ORIGEN DESC_UNIT ENVIO_UNIT TAX_UNIT AJUSTE_UNIT COSTO_UNIT IMPORTE');
    lines.push('IMPORTE');

    invoice.items.forEach((item) => {
      lines.push(`[${item.sku || 'AE-ITEM'}] ${item.description}`);
      lines.push(formatDecimalComma(item.quantity || 1));
      lines.push('Unidades');
      lines.push(`$ ${formatDecimalComma((item.sourceUnitPrice ?? item.unitPrice) || 0)}`);
      lines.push(`$ ${formatDecimalComma(-Math.abs(toNumber(item.allocatedDiscount)))}`);
      lines.push(`$ ${formatDecimalComma(item.allocatedShipping || 0)}`);
      lines.push(`$ ${formatDecimalComma(item.allocatedTax || 0)}`);
      lines.push(`$ ${formatDecimalComma(item.allocatedAdjustment || 0)}`);
      lines.push(`$ ${formatDecimalComma(item.unitPrice || 0)}`);
      lines.push(`$ ${formatDecimalComma(item.total || 0)}`);
    });

    lines.push(`Total neto $ ${formatDecimalComma(invoice.subtotal || sumSourceItems(invoice.items) || sumItems(invoice.items))}`);
    if (invoice.discount) lines.push(`Descuento coins $ ${formatDecimalComma(-Math.abs(invoice.discount))}`);
    if (invoice.shipping) lines.push(`Envio $ ${formatDecimalComma(invoice.shipping)}`);
    if (invoice.tax) lines.push(`IVA Tax $ ${formatDecimalComma(invoice.tax)}`);
    lines.push(`TOTAL $ ${formatDecimalComma(invoice.total)}`);
    if (invoice.notes) lines.push(invoice.notes);
    return lines.join('\n');
  }

  function buildMachineMetadata(item) {
    const lines = [];
    if (item.productUrl) lines.push(`PRODUCT_URL: ${item.productUrl}`);
    if (item.imageUrl) lines.push(`IMAGE_URL: ${item.imageUrl}`);
    if (item.unitsPerPurchase > 1) {
      lines.push(`SOURCE_PURCHASE_QUANTITY: ${item.sourcePurchaseQuantity}`);
      lines.push(`UNITS_PER_PURCHASE: ${item.unitsPerPurchase}`);
      lines.push(`INVENTORY_UNIT: ${item.inventoryUnit || 'unit'}`);
    }
    if (item.sourceOrderNumbers.length) {
      lines.push(`SOURCE_ORDERS: ${item.sourceOrderNumbers.join(',')}`);
    }
    return escapeHtml(lines.join('\n'));
  }

  function normalizeInvoice(invoice) {
    const items = (invoice.items || []).map((item, index) => {
      const quantity = toNumber(item.quantity) || 1;
      const unitPrice = toNumber(item.unitPrice);
      const total = toNumber(item.total) || roundMoney(quantity * unitPrice);
      const sourceUnitPrice = toNullableNumber(item.sourceUnitPrice) ?? unitPrice;
      const allocatedDiscountTotal = toNullableNumber(item.allocatedDiscountTotal);
      const allocatedShippingTotal = toNullableNumber(item.allocatedShippingTotal);
      const allocatedTaxTotal = toNullableNumber(item.allocatedTaxTotal);
      const allocatedAdjustmentTotal = toNullableNumber(item.allocatedAdjustmentTotal);
      const allocationGranularity = item.allocationGranularity === 'unit' ? 'unit' : '';
      const sourceDescription = String(item.originalDescription || item.description || 'AliExpress item').trim();
      const cleanedDescription = smartProductName(sourceDescription, item);
      const currentDescription = cleanVisibleProductName(item.description);
      const description = cleanedDescription || currentDescription || 'AliExpress item';
      const originalDescription = sourceDescription && sourceDescription !== description
        ? sourceDescription
        : String(item.originalDescription || '').trim();
      return {
        sku: String(item.sku || `AE-${String(index + 1).padStart(3, '0')}`).trim(),
        description,
        originalDescription,
        variant: String(item.variant || '').trim(),
        variantKey: String(item.variantKey || '').trim(),
        quantity,
        unitPrice,
        total,
        sourcePurchaseQuantity: toNumber(item.sourcePurchaseQuantity) || quantity,
        unitsPerPurchase: toNumber(item.unitsPerPurchase) || 1,
        inventoryUnit: item.inventoryUnit || '',
        sourcePurchaseUnitPrice: toNullableNumber(item.sourcePurchaseUnitPrice),
        sourceOrderNumbers: Array.isArray(item.sourceOrderNumbers) ? item.sourceOrderNumbers : [],
        sourceUnitPrice,
        sourceTotal: toNullableNumber(item.sourceTotal) ?? roundMoney(sourceUnitPrice * quantity),
        allocatedDiscount: normalizeAllocationUnit(item.allocatedDiscount, allocatedDiscountTotal, quantity, allocationGranularity),
        allocatedDiscountTotal,
        allocatedShipping: normalizeAllocationUnit(item.allocatedShipping, allocatedShippingTotal, quantity, allocationGranularity),
        allocatedShippingTotal,
        allocatedTax: normalizeAllocationUnit(item.allocatedTax, allocatedTaxTotal, quantity, allocationGranularity),
        allocatedTaxTotal,
        allocatedAdjustment: normalizeAllocationUnit(item.allocatedAdjustment, allocatedAdjustmentTotal, quantity, allocationGranularity),
        allocatedAdjustmentTotal,
        allocationGranularity: 'unit',
        itemId: item.itemId || '',
        productUrl: item.productUrl || '',
        imageUrl: item.imageUrl || '',
        embeddedImageUrl: item.embeddedImageUrl || '',
      };
    });

    return {
      supplierName: invoice.supplierName || 'AliExpress Marketplace',
      supplierTaxId: invoice.supplierTaxId || '',
      orderNumber: invoice.orderNumber || '',
      orderDate: invoice.orderDate || '',
      currency: 'CLP',
      subtotal: toNullableNumber(invoice.subtotal),
      shipping: toNullableNumber(invoice.shipping),
      tax: toNullableNumber(invoice.tax),
      discount: toNullableNumber(invoice.discount),
      total: toNumber(invoice.total) || sumItems(items),
      componentDifference: toNullableNumber(invoice.componentDifference)
        ?? toNullableNumber(invoice.allocation && invoice.allocation.componentDifference),
      notes: invoice.notes || '',
      pageUrl: invoice.pageUrl || '',
      items,
    };
  }

  function normalizeAllocationUnit(unitValue, totalValue, quantity, granularity) {
    const total = toNullableNumber(totalValue);
    if (total !== null) return roundMoney(total / (quantity || 1));
    const unit = toNullableNumber(unitValue);
    if (unit === null) return null;
    return granularity === 'unit' ? unit : roundMoney(unit / (quantity || 1));
  }

  function smartProductName(description, item = {}) {
    const raw = String(description || '').replace(/\s+/g, ' ').trim();
    if (!raw) return '';

    const base = stripAliExpressTitleNoise(raw);
    const normalized = normalizeNameKey(base);
    const brand = extractCatalogBrand(base);
    const variant = extractTrailingVariant(base);

    if (/\b(pastillas?(?:\s+de)?\s+freno|brake\s+pads?)\b/.test(normalized)) {
      return compactName([
        'Pastillas de freno',
        brand,
        brakePadModelLabel(base),
        '(par)',
      ]);
    }

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

  function brakePadModelLabel(value) {
    const match = String(value || '').match(/\b([A-Z]{1,6}-\d{1,4}[A-Z]?)\b/i);
    return match ? match[1].toUpperCase() : '';
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

  function renderError(message) {
    root.innerHTML = `<section class="section"><h1>${escapeHtml(message)}</h1></section>`;
  }

  function copyOcrText() {
    if (!currentInvoice) return;
    navigator.clipboard.writeText(buildOcrText(currentInvoice));
  }

  function downloadJson() {
    if (!currentInvoice) return;
    downloadBlob(
      JSON.stringify(currentInvoice, null, 2),
      `aliexpress-invoice-${safeFilePart(currentInvoice.orderNumber)}.json`,
      'application/json',
    );
  }

  function downloadHtml() {
    if (!currentInvoice) return;
    const html = `<!doctype html>\n${document.documentElement.outerHTML}`;
    downloadBlob(html, `aliexpress-invoice-${safeFilePart(currentInvoice.orderNumber)}.html`, 'text/html');
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

  function formatMoney(value, currency) {
    const number = toNumber(value);
    const rounded = Math.round(number);
    return `$ ${rounded.toLocaleString('es-CL')}`;
  }

  function formatUnitMoney(value, currency) {
    const number = toNumber(value);
    if (Math.abs(number - Math.round(number)) < 0.005) return formatMoney(number, currency);
    return `$ ${number.toLocaleString('es-CL', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  }

  function formatOptionalMoney(value, currency) {
    const number = toNumber(value);
    if (Math.abs(number) < 0.01) return '—';
    return formatMoney(number, currency);
  }

  function formatOptionalUnitMoney(value, currency) {
    const number = toNumber(value);
    if (Math.abs(number) < 0.005) return '—';
    return formatUnitMoney(number, currency);
  }

  function formatQuantity(value) {
    return (Number(value) || 0).toLocaleString('es-CL', { maximumFractionDigits: 2 });
  }

  function formatDate(isoDate) {
    const [year, month, day] = String(isoDate || '').split('-');
    return year && month && day ? `${day}/${month}/${year}` : '';
  }

  function formatDecimalComma(value) {
    return (Number(value) || 0).toFixed(2).replace('.', ',');
  }

  function sumItems(items) {
    return roundMoney((items || []).reduce((sum, item) => sum + toNumber(item.total), 0));
  }

  function sumSourceItems(items) {
    return roundMoney((items || []).reduce((sum, item) => {
      const sourceTotal = toNullableNumber(item.sourceTotal);
      return sum + (sourceTotal === null ? toNumber(item.total) : sourceTotal);
    }, 0));
  }

  function roundMoney(value) {
    return Math.round((Number(value) || 0) * 100) / 100;
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

  function escapeHtml(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function escapeAttr(value) {
    return escapeHtml(value);
  }

  function safeFilePart(value) {
    return String(value || 'invoice').replace(/[^a-z0-9_-]+/gi, '-').replace(/^-+|-+$/g, '') || 'invoice';
  }

  const testing = Object.freeze({
    normalizeInvoice,
    smartProductName,
    buildInvoiceMarkup,
    formatMoney,
    formatUnitMoney,
    formatOptionalUnitMoney,
  });
  globalThis.__ALIEXPRESS_INVOICE_RENDERER_TESTING__ = testing;
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = testing;
  }
}());
