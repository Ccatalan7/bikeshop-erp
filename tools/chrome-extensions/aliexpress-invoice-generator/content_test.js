const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function loadTestingBridge() {
  const sandbox = {
    URL,
    console,
    location: {
      href: 'https://www.aliexpress.com/p/order/index.html',
      pathname: '/p/order/index.html',
    },
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  const source = fs.readFileSync(path.join(__dirname, 'content.js'), 'utf8');
  vm.runInContext(source, sandbox, { filename: 'content.js' });
  return sandbox.__ALIEXPRESS_INVOICE_BRIDGE__._testing;
}

const parser = loadTestingBridge();

test('recognizes current order number labels', () => {
  assert.equal(parser.extractOrderListNumber('Order # 8193027456112345'), '8193027456112345');
  assert.equal(parser.extractOrderListNumber('Número de pedido: 8193027456112346'), '8193027456112346');
  assert.equal(parser.extractOrderListNumber('Purchase ID 8193027456112347'), '8193027456112347');
});

test('reads order IDs from detail links when the card hides the label', () => {
  assert.equal(
    parser.extractOrderNumberFromHref('/p/order/detail.html?orderId=8193027456112345'),
    '8193027456112345',
  );
  assert.equal(
    parser.extractOrderNumberFromHref('https://www.aliexpress.com/order/detail/8193027456112346'),
    '8193027456112346',
  );
  assert.equal(
    parser.extractOrderNumberFromHref('https://www.aliexpress.com/p/message/index.html?orderId=8193027456112347&accountid=2675472708'),
    '8193027456112347',
  );
  assert.equal(
    parser.extractOrderNumberFromHref('https://www.aliexpress.com/store/1103059752'),
    '',
  );
  assert.equal(
    parser.extractOrderNumberFromHref('https://www.aliexpress.com/store/1104402704/pages/all-items.html'),
    '',
  );
  assert.equal(
    parser.extractOrderNumberFromHref('https://www.aliexpress.com/item/1005006114758950.html'),
    '',
  );
});

test('uses only a real order-detail URL and never a message thread', () => {
  const messageUrl = 'https://www.aliexpress.com/p/message/index.html?fromCode=order&orderId=8211744661738042';
  const detailUrl = 'https://www.aliexpress.com/p/order/detail.html?orderId=8211744661738042';
  const anchor = (href) => ({ href, getAttribute() { return href; } });

  assert.equal(
    parser.findOrderListDetailUrl({ querySelectorAll: () => [anchor(messageUrl), anchor(detailUrl)] }, '8211744661738042'),
    detailUrl,
  );
  assert.equal(
    parser.findOrderListDetailUrl({ querySelectorAll: () => [anchor(messageUrl)] }, '8211744661738042'),
    detailUrl,
  );
});

test('recognizes purchase dates without confusing delivery labels', () => {
  assert.equal(parser.extractOrderListDate(['Order placed: Jul 18, 2026']), '2026-07-18');
  assert.equal(parser.extractOrderListDate(['Placed on 18 Jul 2026']), '2026-07-18');
  assert.equal(parser.extractOrderListDate(['Fecha de compra: 18/07/2026']), '2026-07-18');
  assert.equal(
    parser.extractOrderListDate(['Estimated delivery: Jul 29, 2026', 'Order placed Jul 18, 2026']),
    '2026-07-18',
  );
});

test('recognizes current load-more labels in English and Spanish', () => {
  assert.ok(parser.loadMoreTextScore('View 10 more orders') > 0);
  assert.ok(parser.loadMoreTextScore('Show more orders') > 0);
  assert.ok(parser.loadMoreTextScore('Ver más pedidos') > 0);
  assert.equal(parser.loadMoreTextScore('Order details'), 0);
});

test('reads the complete visible AliExpress cost breakdown', () => {
  const totals = parser.extractTotalsFromTextBlob([
    'Subtotal',
    '$10.200',
    'Shipping',
    '$1',
    'AliExpress Coupons',
    '-$1.133',
    'Tax',
    '$1.723',
    'Total',
    '$10.790',
  ].join('\n'));

  assert.equal(totals.subtotal.amount, 10200);
  assert.equal(totals.shipping.amount, 1);
  assert.equal(totals.discount.amount, 1133);
  assert.equal(totals.tax.amount, 1723);
  assert.equal(totals.total.amount, 10790);
  assert.equal(parser.cardTotalsBalance(totals), true);
});

test('collapses duplicate DOM observations of one purchased row', () => {
  const items = parser.dedupeExtractedItems([
    {
      sku: 'AE-14758950',
      itemId: '1005000014758950',
      description: 'ZTTO 4 pares de pastillas de freno MS-01B',
      quantity: 2,
      unitPrice: 5100,
      total: 10200,
      imageUrl: 'https://ae01.alicdn.com/pads.jpg',
      productUrl: 'https://www.aliexpress.com/item/1005000014758950.html',
    },
    {
      sku: 'AE-14758950',
      itemId: '1005000014758950',
      description: 'ZTTO 4 pares de pastillas de freno MS-01B',
      quantity: 2,
      unitPrice: 5100,
      total: 10200,
      imageUrl: '',
      productUrl: '',
    },
  ]);

  assert.equal(items.length, 1);
  assert.match(items[0].imageUrl, /pads\.jpg/);
});

test('list extraction collapses image and text observations of one product', () => {
  const base = {
    sku: 'AE-14758950',
    itemId: '1005006114758950',
    description: 'ZTTO 4 pares de pastillas de freno MS-01B',
    quantity: 2,
    unitPrice: 5100,
    total: 10200,
    productUrl: 'https://www.aliexpress.com/item/1005006114758950.html',
  };
  const items = parser.collapseOrderListItemCandidates([
    { ...base, imageUrl: 'https://ae01.alicdn.com/pads.jpg', _y: 20, _x: 10 },
    { ...base, imageUrl: '', _y: 20, _x: 10 },
  ]);

  assert.equal(items.length, 1);
  assert.match(items[0].imageUrl, /pads\.jpg/);
});

test('side panel keeps one primary flow and separates fallback tools', () => {
  const html = fs.readFileSync(path.join(__dirname, 'sidepanel.html'), 'utf8');
  assert.match(html, /data-tab="invoice"/);
  assert.match(html, /data-tab="vision"/);
  assert.match(html, /data-tab="tools"/);
  assert.match(html, />Buscar compras</);
  assert.match(html, />Crear factura para OCR</);
  assert.doesNotMatch(html, />JSON bulk</);
});

test('content extractor prints the list and detail debug stages', () => {
  const source = fs.readFileSync(path.join(__dirname, 'content.js'), 'utf8');

  assert.match(source, /\[AE-DEBUG\]\[content\]/);
  assert.match(source, /list\.scroll\.cycle/);
  assert.match(source, /list\.card\.extracted/);
  assert.match(source, /detail\.extract\.complete/);
});
