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

  assert.equal(invoice.items[0].description, 'Pastillas de freno ZTTO MS-01B');
  assert.equal(invoice.items[0].sourcePurchaseQuantity, 2);
  assert.equal(invoice.items[0].quantity, 2);
  assert.equal(invoice.items[0].rawPackCount, 4);
  assert.equal(invoice.items[0].rawUnitToken, 'pares');
  assert.equal(invoice.items[0].unitsPerPurchase, 1);
  assert.equal(invoice.items[0].sourceUnitPrice, 5100);
  assert.equal(invoice.items[0].unitPrice, 5395);
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
  assert.match(markup, /Evidencia proveedor: 2 compra\(s\) × opción 4 pares; conversión pendiente del producto/);
  assert.match(markup, /RAW_PACK_COUNT: 4/);
  assert.match(markup, /RAW_UNIT_TOKEN: pares/);
  assert.match(markup, /\$ 5\.100/);
  assert.match(markup, /\$ -566,52/);
  assert.match(markup, /\$ 861,52/);
  assert.match(markup, /\$ 5\.395/);
  assert.match(markup, /Descuento \/ coins/);
  assert.match(markup, /IVA \/ Tax/);
  assert.match(markup, /Saldo adeudado/);
});

test('extracts only one explicit selected pack and rejects ranges or menus', () => {
  assert.deepEqual(
    renderer.extractRawPackEvidence('160mm 2PCS'),
    {
      rawPackCount: 2,
      rawUnitToken: 'pcs',
      hasEvidence: true,
      mentionsPackUnit: true,
    },
  );
  assert.equal(renderer.extractRawPackEvidence('100-500 pieces').hasEvidence, false);
  assert.equal(renderer.extractRawPackEvidence('1/2/4PCS').hasEvidence, false);
  assert.equal(renderer.extractRawPackEvidence('Black').mentionsPackUnit, false);
});

test('selected variant outranks a contradictory curated listing title', () => {
  const invoice = renderer.normalizeInvoice({
    total: 100,
    items: [{
      description: 'Rotor disponible en 1/2/4PCS (160mm 2PCS)',
      lineTitle: 'Rotor disponible en 1/2/4PCS',
      variant: '160mm 2PCS',
      rawPackCount: 4,
      rawUnitToken: 'pieces',
      quantity: 1,
      total: 100,
    }],
  });

  assert.equal(invoice.items[0].quantity, 1);
  assert.equal(invoice.items[0].rawPackCount, 2);
  assert.equal(invoice.items[0].rawUnitToken, 'pcs');
});

test('OCR text transports source quantity and raw pack evidence', () => {
  const invoice = renderer.normalizeInvoice(fixtureInvoice());
  const text = renderer.buildOcrText(invoice);

  assert.match(text, /SOURCE_PURCHASE_QUANTITY: 2/);
  assert.match(text, /RAW_PACK_COUNT: 4/);
  assert.match(text, /RAW_UNIT_TOKEN: pares/);
  assert.doesNotMatch(text, /UNITS_PER_PURCHASE/);
});

test('conflicting pack evidence is transported and cannot be re-inferred', () => {
  const invoice = renderer.normalizeInvoice({
    total: 100,
    items: [{
      description: 'Rotor RT56 2PCS',
      variant: '2PCS',
      quantity: 1,
      total: 100,
      rawPackCount: 2,
      rawUnitToken: 'pcs',
      rawPackEvidenceConflict: true,
    }],
  });
  const item = invoice.items[0];

  assert.equal(item.rawPackCount, null);
  assert.equal(item.rawUnitToken, null);
  assert.equal(item.rawPackEvidenceConflict, true);
  const text = renderer.buildOcrText(invoice);
  assert.match(text, /RAW_PACK_EVIDENCE_CONFLICT: true/);
  assert.doesNotMatch(text, /RAW_PACK_COUNT:/);
  assert.doesNotMatch(text, /RAW_UNIT_TOKEN:/);
});
