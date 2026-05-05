(function () {
  'use strict';

  const STORAGE_PREFIX = 'aliexpressInvoiceDraft:';
  const root = document.getElementById('invoiceRoot');
  const toolbarMeta = document.getElementById('toolbarMeta');
  let currentInvoice = null;

  document.getElementById('printButton').addEventListener('click', () => window.print());
  document.getElementById('downloadHtmlButton').addEventListener('click', downloadHtml);
  document.getElementById('downloadJsonButton').addEventListener('click', downloadJson);
  document.getElementById('copyTextButton').addEventListener('click', copyOcrText);

  loadInvoice();

  async function loadInvoice() {
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
    toolbarMeta.textContent = currentInvoice.orderNumber ? `Pedido ${currentInvoice.orderNumber}` : '';
    renderInvoice(currentInvoice);
  }

  function renderInvoice(invoice) {
    const itemRows = invoice.items.map((item, index) => `
      <tr>
        <td class="index-cell">${index + 1}</td>
        <td>
          <div class="article-cell">
            ${item.imageUrl ? `<img class="item-image" src="${escapeAttr(item.imageUrl)}" alt="" referrerpolicy="no-referrer">` : '<div class="item-image-empty"></div>'}
            <div class="article-copy">
              <strong>${escapeHtml(item.description || 'AliExpress item')}</strong>
              <div class="muted">SKU: ${escapeHtml(item.sku || 'AE-ITEM')}</div>
              ${item.itemId ? `<div class="muted">Item ID: ${escapeHtml(item.itemId)}</div>` : ''}
            </div>
          </div>
        </td>
        <td class="numeric">${formatQuantity(item.quantity)}</td>
        <td class="numeric">${formatMoney(item.unitPrice, invoice.currency)}</td>
        <td class="numeric">${formatMoney(item.total, invoice.currency)}</td>
      </tr>
    `).join('');

    const itemSubtotal = sumItems(invoice.items);
    const subtotal = invoice.subtotal || itemSubtotal;
    const shipping = invoice.shipping || Math.max(0, roundMoney(invoice.total - subtotal - (invoice.tax || 0) + (invoice.discount || 0)));
    const paidAmount = invoice.total;
    const balance = Math.max(0, roundMoney(invoice.total - paidAmount));

    root.innerHTML = `
      <header class="invoice-header">
        <div class="brand-mark">
          <img class="brand-logo" src="https://vinabike.cl/vinabike-logo.png" alt="Vinabike">
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
              <th>Artículo &amp; Descripción</th>
              <th class="numeric">Cantidad</th>
              <th class="numeric">Tarifa</th>
              <th class="numeric">Importe</th>
            </tr>
          </thead>
          <tbody>${itemRows}</tbody>
        </table>
      </section>

      <section class="section totals">
        <div class="totals-row"><span>Subtotal (Neto)</span><span>${formatMoney(subtotal, invoice.currency)}</span></div>
        ${invoice.discount ? `<div class="totals-row"><span>Descuento</span><span>${formatMoney(-invoice.discount, invoice.currency)}</span></div>` : ''}
        ${shipping > 0 ? `<div class="totals-row"><span>Shipping</span><span>${formatMoney(shipping, invoice.currency)}</span></div>` : ''}
        ${invoice.tax ? `<div class="totals-row"><span>IVA / Tax</span><span>${formatMoney(invoice.tax, invoice.currency)}</span></div>` : ''}
        <div class="totals-row grand-total"><span>TOTAL</span><span>${formatMoney(invoice.total, invoice.currency)}</span></div>
        <div class="totals-row paid-row"><span>Pago realizado</span><span>${formatMoney(paidAmount, invoice.currency)}</span></div>
        <div class="totals-row balance-row"><span>Saldo adeudado</span><span>${formatMoney(balance, invoice.currency)}</span></div>
      </section>
    `;

    wireImageFallbacks();
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

  function normalizeInvoice(invoice) {
    const items = (invoice.items || []).map((item, index) => {
      const quantity = toNumber(item.quantity) || 1;
      const unitPrice = toNumber(item.unitPrice);
      const total = toNumber(item.total) || roundMoney(quantity * unitPrice);
      return {
        sku: String(item.sku || `AE-${String(index + 1).padStart(3, '0')}`).trim(),
        description: String(item.description || 'AliExpress item').trim(),
        quantity,
        unitPrice,
        total,
        itemId: item.itemId || '',
        productUrl: item.productUrl || '',
        imageUrl: item.imageUrl || '',
      };
    });

    return {
      supplierName: invoice.supplierName || 'AliExpress Marketplace',
      supplierTaxId: invoice.supplierTaxId || '',
      orderNumber: invoice.orderNumber || '',
      orderDate: invoice.orderDate || new Date().toISOString().slice(0, 10),
      currency: 'CLP',
      subtotal: toNullableNumber(invoice.subtotal),
      shipping: toNullableNumber(invoice.shipping),
      tax: toNullableNumber(invoice.tax),
      discount: toNullableNumber(invoice.discount),
      total: toNumber(invoice.total) || sumItems(items),
      notes: invoice.notes || '',
      pageUrl: invoice.pageUrl || '',
      items,
    };
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
}());