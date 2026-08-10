const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function loadBridge({ chromeExtension = false } = {}) {
  function FakeXMLHttpRequest() {}
  FakeXMLHttpRequest.prototype.open = function open() {};
  FakeXMLHttpRequest.prototype.send = function send() {};
  const sandbox = {
    URL,
    console,
    fetch: async () => ({ ok: true }),
    XMLHttpRequest: FakeXMLHttpRequest,
    location: {
      href: 'https://www.aliexpress.com/p/order/index.html',
      pathname: '/p/order/index.html',
    },
  };
  if (chromeExtension) {
    sandbox.chrome = {
      runtime: {
        onMessage: {
          addListener() {},
          removeListener() {},
        },
      },
    };
  }
  sandbox.globalThis = sandbox;
  sandbox.window = sandbox;
  vm.createContext(sandbox);
  const source = fs.readFileSync(path.join(__dirname, 'content.js'), 'utf8');
  vm.runInContext(source, sandbox, { filename: 'content.js' });
  return { bridge: sandbox.__ALIEXPRESS_INVOICE_BRIDGE__, sandbox };
}

function loadTestingBridge() {
  return loadBridge().bridge._testing;
}

async function installOrdersApiFixture(pages) {
  const { bridge, sandbox } = loadBridge();
  await Promise.resolve();
  await sandbox.fetch('https://mtop.aliexpress.com/order/list', {
    method: 'POST',
    body: `data=${encodeURIComponent(JSON.stringify({
      params: JSON.stringify({ pageIndex: 1 }),
    }))}`,
  });
  sandbox.lib = {
    mtop: {
      request: async ({ data }) => {
        const pageIndex = JSON.parse(data.params).pageIndex;
        return { data: { data: pages[pageIndex] || {} } };
      },
    },
  };
  return bridge;
}

const parser = loadTestingBridge();

test('ERP WebView instala la sonda al cargar y Chrome conserva el opt-in', async () => {
  const erpBridge = loadBridge().bridge;
  await Promise.resolve();
  const erp = erpBridge.ordersApiProbeInstall();
  assert.equal(erp.installed, true);
  assert.equal(erp.alreadyInstalled, true);

  const chrome = loadBridge({ chromeExtension: true })
    .bridge.ordersApiProbeInstall();
  assert.equal(chrome.installed, true);
  assert.equal(chrome.alreadyInstalled, false);
});

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
  assert.ok(items[0].variantKey, 'every supplier item exposes a durable variant key');
});

test('keeps same listing and title as distinct rows when explicit variants differ', () => {
  const base = {
    sku: 'AE-337769267',
    itemId: '1005009937769267',
    description: 'Tee WAKE 31.8mm',
    quantity: 1,
    unitPrice: 7172,
    total: 7172,
    productUrl: 'https://www.aliexpress.com/item/1005009937769267.html',
  };
  const items = parser.dedupeExtractedItems([
    { ...base, variant: 'Black', variantKey: 'black' },
    { ...base, variant: 'Purple', variantKey: 'purple' },
  ]);

  assert.equal(items.length, 2);
  assert.deepEqual(
    Array.from(items, (item) => item.variantKey),
    ['black', 'purple'],
  );
  assert.deepEqual(
    Array.from(items, (item) => item.variant),
    ['Black', 'Purple'],
  );
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

test('la API de pedidos se lee sin inventar fechas ni montos', () => {

  // Fechas: la forma real de AliExpress, y un formato desconocido que debe
  // quedar vacío en vez de convertirse en una fecha plausible.
  assert.equal(parser.parseApiOrderDate('Jun 15, 2026'), '2026-06-15');
  assert.equal(parser.parseApiOrderDate('Apr 6, 2026'), '2026-04-06');
  assert.equal(parser.parseApiOrderDate('15/06/2026'), '');

  // Montos: en CLP la coma agrupa miles y no hay decimales.
  assert.equal(parser.parseApiMoney('CLP 13,941'), 13941);
  assert.equal(parser.parseApiMoney('CLP 6,590'), 6590);
  assert.equal(parser.parseApiMoney('$1.234,56'), 1234.56);
  assert.equal(parser.parseApiMoney(''), null);
});

test('un pedido de la API se mapea con sus líneas, imágenes y total', () => {
  const order = parser.mapApiOrder({
    orderId: '8209933206078042',
    orderDateText: 'Apr 6, 2026',
    totalPriceText: 'CLP 9,211',
    currencyCode: 'CLP',
    storeName: 'NEWBIRTH Outdoors Store',
    statusText: 'Completed',
    orderDetailUrl: '//www.aliexpress.com/p/order/detail.html?orderId=8209933206078042',
    orderLines: [
      {
        productId: '1005008734024041',
        quantity: '2',
        formatPriceInfo: 'CLP 3,990',
        itemTitle: 'Luz de bicicleta portátil, linterna IPX6',
        itemDetailUrl: '//www.aliexpress.com/item/1005008734024041.html',
        itemImgUrl: '//ae01.alicdn.com/kf/luz.jpg',
        skuAttrs: [{ value: 'Q01' }],
      },
    ],
  });

  assert.equal(order.orderNumber, '8209933206078042');
  assert.equal(order.orderDate, '2026-04-06');
  assert.equal(order.total, 9211);
  assert.equal(order.items.length, 1);
  assert.equal(order.items[0].quantity, 2);
  assert.equal(order.items[0].unitPrice, 3990);
  assert.equal(order.items[0].total, 7980);
  assert.match(order.items[0].description, /Q01/);
  assert.equal(order.items[0].variant, 'Q01');
  assert.equal(order.items[0].variantKey, 'q01');
  assert.match(order.items[0].imageUrl, /^https:\/\/ae01\.alicdn\.com/);
  assert.match(order.items[0].productUrl, /^https:\/\/www\.aliexpress\.com/);
});

test('un pedido sin identificador no produce una fila fantasma', () => {
  assert.equal(parser.mapApiOrder({ orderDateText: 'Apr 6, 2026' }), null);
});

test('el corte por fecha exige que la página entera sea anterior al día', () => {
  // Reproduce el defecto real del 2026-04-06: la página trae pedidos del día
  // buscado junto a uno más antiguo, y quedan más del mismo día en la página
  // siguiente. Cortar al ver el primer pedido viejo perdía esos pedidos.
  const page = [
    { orderDate: '2026-04-06' },
    { orderDate: '2026-04-06' },
    { orderDate: '2026-04-05' },
  ];
  const newestOnPage = page
    .map((order) => order.orderDate)
    .reduce((newest, date) => (date > newest ? date : newest), '');
  assert.equal(newestOnPage, '2026-04-06');
  assert.equal(newestOnPage < '2026-04-06', false, 'no debe cortar todavía');

  const nextPage = [{ orderDate: '2026-04-05' }, { orderDate: '2026-04-04' }];
  const newestOnNextPage = nextPage
    .map((order) => order.orderDate)
    .reduce((newest, date) => (date > newest ? date : newest), '');
  assert.equal(newestOnNextPage < '2026-04-06', true, 'ahora sí corta');
});

test('dos líneas del mismo producto suman unidades en vez de perderse', () => {
  const order = parser.mapApiOrder({
    orderId: '8209933206118042',
    orderDateText: 'Apr 6, 2026',
    totalPriceText: 'CLP 8,057',
    orderLines: [
      {
        productId: '1005008554962320',
        quantity: '1',
        formatPriceInfo: 'CLP 3,490',
        itemTitle: 'ROCKBROS botella de agua 600ML',
        itemImgUrl: '//ae01.alicdn.com/kf/botella.jpg',
      },
      {
        productId: '1005008554962320',
        quantity: '1',
        formatPriceInfo: 'CLP 3,490',
        itemTitle: 'ROCKBROS botella de agua 600ML',
        itemImgUrl: '//ae01.alicdn.com/kf/botella.jpg',
      },
    ],
  });

  assert.equal(order.items.length, 1);
  assert.equal(order.items[0].quantity, 2);
  assert.equal(order.items[0].total, 6980);
});

test('el corte exige dos páginas seguidas anteriores al día', () => {
  // La lista no viene estrictamente ordenada por fecha: una sola página
  // «vieja» no prueba que el día terminó, y cortar ahí devolvía conjuntos
  // distintos entre corridas del mismo día (6 y luego 8 pedidos del
  // 2026-04-06). Se confirma con una segunda página.
  const target = '2026-04-06';
  const newestOf = (page) => page.reduce((newest, date) => (date > newest ? date : newest), '');

  let pagesPast = 0;
  const cut = (page) => {
    if (newestOf(page) < target) {
      pagesPast += 1;
      return pagesPast >= 2;
    }
    pagesPast = 0;
    return false;
  };

  assert.equal(cut(['2026-04-06', '2026-04-05']), false, 'aún hay del día');
  assert.equal(cut(['2026-04-05', '2026-04-04']), false, 'primera página vieja');
  assert.equal(cut(['2026-04-06']), false, 'reaparece el día: el contador se reinicia');
  assert.equal(cut(['2026-04-03']), false);
  assert.equal(cut(['2026-04-02']), true, 'dos seguidas confirman el fin');
});

test('datesOnly devuelve el índice completo sin materializar pedidos', async () => {
  const dateOnlyFields = (orderId, orderDateText) => {
    const fields = { orderId, orderDateText };
    Object.defineProperties(fields, {
      orderLines: {
        get() { throw new Error('datesOnly no debe leer líneas'); },
      },
      totalPriceText: {
        get() { throw new Error('datesOnly no debe leer montos'); },
      },
    });
    return fields;
  };
  const bridge = await installOrdersApiFixture({
    1: {
      pc_om_list_order_1: {
        fields: dateOnlyFields('8211744661738042', 'Jun 15, 2026'),
      },
      pc_om_list_order_2: {
        fields: dateOnlyFields('8209933206078042', 'Apr 6, 2026'),
      },
    },
    2: {},
  });

  const result = await bridge.ordersApiCollect({ datesOnly: true, maxPages: 30 });

  assert.equal(result.ok, true);
  assert.deepEqual(Array.from(result.orders), []);
  assert.deepEqual(
    Array.from(result.datesWithOrders),
    ['2026-04-06', '2026-06-15'],
  );
  assert.equal(result.coverage.mode, 'dates-only');
  assert.equal(result.coverage.complete, true);
  assert.equal(result.coverage.partial, false);
  assert.equal(result.coverageComplete, true);
  assert.equal(result.coveragePartial, false);
  assert.equal(result.coverage.observedFromDate, '2026-04-06');
  assert.equal(result.coverage.observedToDate, '2026-06-15');
  assert.equal(result.coverage.stopReason, 'sin más pedidos');
});

test('datesOnly declara cobertura parcial cuando alcanza el límite', async () => {
  const bridge = await installOrdersApiFixture({
    1: {
      pc_om_list_order_1: {
        fields: {
          orderId: '8211744661738042',
          orderDateText: 'Jun 15, 2026',
        },
      },
    },
  });

  const result = await bridge.ordersApiCollect({ datesOnly: true, maxPages: 1 });

  assert.equal(result.ok, true);
  assert.equal(result.coverage.mode, 'dates-only');
  assert.equal(result.coverage.complete, false);
  assert.equal(result.coverage.partial, true);
  assert.equal(result.coverageComplete, false);
  assert.equal(result.coveragePartial, true);
  assert.equal(result.coverage.pageLimit, 1);
  assert.equal(result.coverage.pagesRead, 1);
  assert.equal(result.coverage.stopReason, 'max-pages');
});

test('la recolección normal sigue devolviendo sólo los pedidos del día', async () => {
  const fields = (orderId, orderDateText) => ({
    orderId,
    orderDateText,
    totalPriceText: 'CLP 10,790',
    currencyCode: 'CLP',
    orderLines: [],
  });
  const bridge = await installOrdersApiFixture({
    1: {
      pc_om_list_order_1: {
        fields: fields('8211744661738042', 'Jun 15, 2026'),
      },
      pc_om_list_order_2: {
        fields: fields('8209933206078042', 'Apr 6, 2026'),
      },
    },
    2: {},
  });

  const result = await bridge.ordersApiCollect({
    exactDate: '2026-06-15',
    maxPages: 30,
  });

  assert.equal(result.ok, true);
  assert.deepEqual(
    Array.from(result.orders, (order) => order.orderNumber),
    ['8211744661738042'],
  );
  assert.deepEqual(
    Array.from(result.datesWithOrders),
    ['2026-04-06', '2026-06-15'],
  );
  assert.equal(result.coverage.mode, 'exact-date');
  assert.equal(result.coverage.targetDateComplete, true);
});
