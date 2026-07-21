const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function loadPopupTestingBridge() {
  const elements = new Map();
  const fakeElement = () => ({
    value: '',
    checked: false,
    hidden: false,
    dataset: {},
    className: '',
    style: {},
    classList: { add() {}, remove() {}, toggle() {} },
    addEventListener() {},
    setAttribute() {},
    querySelector() { return null; },
    querySelectorAll() { return []; },
    insertAdjacentElement() {},
  });
  const document = {
    body: { dataset: { workspace: '1' }, classList: { add() {} } },
    addEventListener() {},
    querySelectorAll() { return []; },
    getElementById(id) {
      if (!elements.has(id)) elements.set(id, fakeElement());
      return elements.get(id);
    },
    createElement() { return fakeElement(); },
  };
  const sandbox = {
    URL,
    Blob,
    console,
    document,
    location: { search: '' },
    navigator: {},
    window: { setTimeout() {}, clearTimeout() {} },
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(
    fs.readFileSync(path.join(__dirname, 'popup.js'), 'utf8'),
    sandbox,
    { filename: 'popup.js' },
  );
  return sandbox.__ALIEXPRESS_INVOICE_POPUP_TESTING__;
}

const invoice = loadPopupTestingBridge();

test('converts two four-pair packs into eight shop units', () => {
  const item = invoice.normalizeItem({
    sku: 'AE-14758950',
    itemId: '1005000014758950',
    description: 'ZTTO 4 pares de pastillas de freno semimetálicas MS-01B',
    quantity: 2,
    unitPrice: 5100,
    total: 10200,
  });

  assert.equal(item.sourcePurchaseQuantity, 2);
  assert.equal(item.unitsPerPurchase, 4);
  assert.equal(item.quantity, 8);
  assert.equal(item.sourceUnitPrice, 1275);
  assert.equal(item.sourceTotal, 10200);
  assert.equal(item.description, 'Pastillas de freno ZTTO MS-01B (par)');
});

test('preserves a stable listing variant identity for ERP aliases', () => {
  const item = invoice.normalizeItem({
    itemId: '1005009937769267',
    description: 'Rotor RT56 (160mm 2pcs)',
    originalDescription: 'Rotor RT56 (160mm 2pcs)',
    quantity: 1,
    unitPrice: 15000,
    total: 15000,
  });

  assert.equal(item.variant, '160mm 2pcs');
  assert.equal(item.variantKey, '160mm-2pcs');
});

test('deduplicates before allocating the real cost components', () => {
  const raw = {
    sku: 'AE-14758950',
    itemId: '1005000014758950',
    description: 'ZTTO 4 pares de pastillas de freno semimetálicas MS-01B',
    quantity: 2,
    unitPrice: 5100,
    total: 10200,
  };
  const items = invoice.dedupeOrderItems([
    invoice.normalizeItem({ ...raw, imageUrl: 'https://ae01.alicdn.com/pads.jpg' }),
    invoice.normalizeItem({ ...raw, itemId: '', productUrl: '', imageUrl: '' }),
  ]);
  const result = invoice.allocateInvoiceComponents({
    subtotal: 10200,
    shipping: 1,
    tax: 1723,
    discount: 1133,
    total: 10790,
    items,
  });

  assert.equal(result.items.length, 1);
  assert.equal(result.shipping, 1);
  assert.equal(result.tax, 1723);
  assert.equal(result.discount, 1133);
  assert.equal(result.items[0].quantity, 8);
  assert.equal(result.items[0].sourceUnitPrice, 1275);
  assert.equal(result.items[0].unitPrice, 1348.75);
  assert.equal(result.items[0].total, 10790);
  assert.equal(result.items[0].allocatedAdjustment, -0.13);
  assert.equal(result.allocation.componentDifference, -1);
});

test('aggregates the same product across daily orders', () => {
  const base = {
    sku: 'AE-14758950',
    itemId: '1005000014758950',
    description: 'Pastillas ZTTO MS-01B',
    sourcePurchaseQuantity: 2,
    unitsPerPurchase: 4,
    quantity: 8,
    sourcePurchaseUnitPrice: 5100,
    sourceUnitPrice: 1275,
    sourceTotal: 10200,
    allocatedShipping: 0.125,
    allocatedShippingTotal: 1,
    allocatedTax: 215.375,
    allocatedTaxTotal: 1723,
    allocatedDiscount: 141.625,
    allocatedDiscountTotal: 1133,
    unitPrice: 1348.75,
    total: 10790,
  };
  const result = invoice.aggregateDailyItems([
    { ...base, sourceOrderNumbers: ['111111'] },
    { ...base, sourceOrderNumbers: ['222222'] },
  ]);

  assert.equal(result.length, 1);
  assert.equal(result[0].quantity, 16);
  assert.equal(result[0].total, 21580);
  assert.deepEqual(Array.from(result[0].sourceOrderNumbers), ['111111', '222222']);
});

test('keeps a structured persisted debug trace contract', () => {
  const source = fs.readFileSync(path.join(__dirname, 'popup.js'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, 'manifest.json'), 'utf8'));

  assert.equal(manifest.version, '0.4.6');
  assert.match(source, /\[AE-DEBUG\]\[popup\]/);
  assert.match(source, /aliexpressInvoiceLastDebugRun/);
  assert.match(source, /bulk\.collect\.raw-result/);
  assert.match(source, /bulk\.enrichment\.order\.merged/);
  assert.match(source, /bulk\.combine\.output/);
});

test('rejects message threads and resolves the canonical order detail URL', () => {
  const messageUrl = 'https://www.aliexpress.com/p/message/index.html?fromCode=order&orderId=8211744661738042&bizContext=orderDetail';
  const detailUrl = 'https://www.aliexpress.com/p/order/detail.html?orderId=8211744661738042';

  assert.equal(invoice.isUsableOrderDetailUrl(messageUrl, '8211744661738042'), false);
  assert.equal(invoice.isUsableOrderDetailUrl(detailUrl, '8211744661738042'), true);
  assert.equal(
    invoice.resolveOrderDetailUrl({ orderNumber: '8211744661738042', pageUrl: messageUrl }),
    detailUrl,
  );
});

test('keeps one best copy of each AliExpress order', () => {
  const orderNumber = '8211744661738042';
  const result = invoice.dedupeBulkOrdersByOrderNumber([
    {
      orderNumber,
      pageUrl: `https://www.aliexpress.com/p/message/index.html?orderId=${orderNumber}`,
      items: [{ description: `AliExpress order ${orderNumber}`, quantity: 1, total: 0 }],
    },
    {
      orderNumber,
      pageUrl: `https://www.aliexpress.com/p/order/detail.html?orderId=${orderNumber}`,
      items: [{ description: 'Pastillas ZTTO', itemId: '1005006114758950', quantity: 2, total: 10200 }],
    },
  ]);

  assert.equal(result.length, 1);
  assert.match(result[0].pageUrl, /\/p\/order\/detail\.html/);
});
