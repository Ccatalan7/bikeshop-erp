const test = require('node:test');
const assert = require('node:assert/strict');

const renderer = require('./invoice.js');

function fixtureInvoice() {
  return {
    supplierName: 'AliExpress Marketplace',
    orderNumber: 'AE-BULK-738042-838042-6',
    orderDate: '2026-06-15',
    subtotal: 10200,
    shipping: 1,
    tax: 1723,
    discount: 1133,
    componentDifference: -1,
    total: 10790,
    items: [
      {
        sku: 'AE-14758950',
        description:
          'ZTTO 4 pares de pastillas de freno silenciosas semimetálicas MTB pastilla de freno de disco hidráulico Universal para M355 XT M6100 mt200 guía E9 MT6 freno de disco (MS-01B)',
        quantity: 8,
        sourcePurchaseQuantity: 2,
        unitsPerPurchase: 4,
        inventoryUnit: 'par',
        sourceUnitPrice: 1275,
        allocatedDiscount: 141.63,
        allocatedShipping: 0.13,
        allocatedTax: 215.38,
        allocatedAdjustment: -0.13,
        allocationGranularity: 'unit',
        unitPrice: 1348.75,
        total: 10790,
        itemId: '1005000014758950',
        imageUrl: 'https://ae01.alicdn.com/pads.jpg',
        embeddedImageUrl: 'data:image/png;base64,AA==',
      },
    ],
  };
}

test('normalizes the same compact product name used by the invoice', () => {
  const invoice = renderer.normalizeInvoice(fixtureInvoice());

  assert.equal(invoice.items[0].description, 'Pastillas de freno ZTTO MS-01B (par)');
  assert.equal(invoice.items[0].quantity, 8);
  assert.equal(invoice.items[0].unitsPerPurchase, 4);
});

test('renders the complete eleven-column Chrome invoice contract', () => {
  const invoice = renderer.normalizeInvoice(fixtureInvoice());
  const markup = renderer.buildInvoiceMarkup(invoice);

  assert.equal((markup.match(/<th\b/g) || []).length, 11);
  for (const heading of [
    'Imagen',
    'Artículo &amp; Descripción',
    'Tarifa origen',
    'Desc./coins u.',
    'Envío u.',
    'Tax u.',
    'Ajuste u.',
    'Costo unit. calc.',
    'Importe',
  ]) {
    assert.match(markup, new RegExp(heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(markup, /https:\/\/ae01\.alicdn\.com\/pads\.jpg/);
  assert.match(markup, /<img class="item-image" src="data:image\/png;base64,AA=="/);
  assert.doesNotMatch(markup, /&quot;embeddedImageUrl&quot;/);
  assert.match(markup, /Compra AliExpress: 2 × 4 pares = 8 pares/);
  assert.match(markup, /\$ 1\.275/);
  assert.match(markup, /\$ -141,63/);
  assert.match(markup, /\$ 215,38/);
  assert.match(markup, /\$ 1\.348,75/);
  assert.match(markup, /Descuento \/ coins/);
  assert.match(markup, /IVA \/ Tax/);
  assert.match(markup, /Saldo adeudado/);
});
