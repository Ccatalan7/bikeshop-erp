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

async function installOrdersApiFixture(pages, options = {}) {
  const { bridge, sandbox } = loadBridge();
  let requestIndex = 0;
  const orderCountFor = (page) => Object.keys(page || {})
    .filter((key) => /^pc_om_list_order_\d+$/.test(key)).length;
  const fixturePageSize = Number(options.pageSize) || Math.max(
    1,
    ...Object.values(pages).filter((page) => !(page instanceof Error))
      .map(orderCountFor),
  );
  const templateParams = options.templateParams || {
    pageIndex: 1,
    pageSize: fixturePageSize,
    statusTab: 'all',
    timeOption: 'all',
    searchOption: 'order',
    searchInput: '',
  };
  await Promise.resolve();
  await sandbox.fetch('https://mtop.aliexpress.com/order/list', {
    method: 'POST',
    body: `data=${encodeURIComponent(JSON.stringify({
      params: JSON.stringify(templateParams),
    }))}`,
  });
  sandbox.lib = {
    mtop: {
      request: async ({ data }) => {
        requestIndex += 1;
        const parsedParams = JSON.parse(data.params);
        if (Array.isArray(options.requests)) options.requests.push(parsedParams);
        const pageIndex = parsedParams.pageIndex;
        const page = typeof options.pageProvider === 'function'
          ? options.pageProvider({ pageIndex, parsedParams, requestIndex })
          : pages[pageIndex];
        if (page instanceof Error) throw page;
        const modules = { ...(page || {}) };
        const orderCount = orderCountFor(modules);
        const explicitHasMore = options.hasMoreByPage &&
          Object.prototype.hasOwnProperty.call(options.hasMoreByPage, pageIndex)
          ? options.hasMoreByPage[pageIndex]
          : null;
        const hasMore = explicitHasMore === null
          ? (orderCount === 0
            ? false
            : (Object.prototype.hasOwnProperty.call(pages, pageIndex + 1) || true))
          : explicitHasMore;
        const responsePageIndex = options.responsePageIndexByPage &&
          Object.prototype.hasOwnProperty.call(options.responsePageIndexByPage, pageIndex)
          ? options.responsePageIndexByPage[pageIndex]
          : pageIndex;
        const responsePageSize = options.responsePageSizeByPage &&
          Object.prototype.hasOwnProperty.call(options.responsePageSizeByPage, pageIndex)
          ? options.responsePageSizeByPage[pageIndex]
          : fixturePageSize;
        modules.pc_om_list_body_fixture = {
          fields: {
            pageIndex: responsePageIndex,
            pageSize: responsePageSize,
            hasMore,
          },
        };
        modules.pc_om_list_header_action_fixture = {
          fields: {
            statusTab: options.responseStatusByPage &&
              options.responseStatusByPage[pageIndex] ||
              parsedParams.statusTab || 'all',
            timeOption: options.responseTimeByPage &&
              options.responseTimeByPage[pageIndex] ||
              parsedParams.timeOption || 'all',
            searchOption: options.responseSearchByPage &&
              options.responseSearchByPage[pageIndex] ||
              parsedParams.searchOption || 'order',
            searchInput: parsedParams.searchInput || '',
          },
        };
        return { data: { data: modules } };
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

test('dos líneas del mismo producto suman unidades en vez de perderse', () => {
  const order = parser.mapApiOrder({
    orderId: '8209933206118042',
    orderDateText: 'Apr 6, 2026',
    totalPriceText: 'CLP 8,057',
    orderLines: [
      {
        productId: '1005008554962320',
        skuId: '12000049999999999',
        quantity: '1',
        formatPriceInfo: 'CLP 3,490',
        itemTitle: 'ROCKBROS botella de agua 600ML',
        itemImgUrl: '//ae01.alicdn.com/kf/botella.jpg',
      },
      {
        productId: '1005008554962320',
        skuId: '12000049999999999',
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

test('la API no agrega líneas sin una variante inmutable', () => {
  const order = parser.mapApiOrder({
    orderId: '8209933206118043',
    orderDateText: 'Apr 6, 2026',
    totalPriceText: 'CLP 6,980',
    orderLines: [
      {
        productId: '1005008554962320',
        quantity: '1',
        formatPriceInfo: 'CLP 3,490',
        itemTitle: 'Producto con variante no estructurada',
        skuAttrs: [{ value: 'Black' }],
      },
      {
        productId: '1005008554962320',
        quantity: '1',
        formatPriceInfo: 'CLP 3,490',
        itemTitle: 'Producto con variante no estructurada',
        skuAttrs: [{ value: 'Negro' }],
      },
    ],
  });

  assert.equal(order.items.length, 2);
  assert.deepEqual(
    Array.from(order.items, (item) => item.sourceApiLineOrdinal),
    [1, 2],
  );
});

test('la API agrega sólo la misma variante inmutable', () => {
  const base = {
    productId: '1005007336672891',
    formatPriceInfo: 'CLP 7,172',
    itemTitle: 'WAKE Tee 31.8mm',
    itemImgUrl: '//ae01.alicdn.com/kf/wake.jpg',
  };
  const order = parser.mapApiOrder({
    orderId: '8209933206999999',
    orderDateText: 'Jun 28, 2025',
    totalPriceText: 'CLP 21,516',
    orderLines: [
      {
        ...base,
        quantity: '1',
        skuId: '12000040000000001',
        skuAttrs: [{ value: 'Red' }],
      },
      {
        ...base,
        quantity: '1',
        skuId: '12000040000000002',
        skuAttrs: [{ value: 'Purple' }],
      },
      {
        ...base,
        quantity: '1',
        skuId: '12000040000000001',
        skuAttrs: [{ value: 'Rojo' }],
      },
    ],
  });

  assert.equal(order.items.length, 2);
  assert.deepEqual(
    Array.from(order.items, (item) => [item.variantKey, item.quantity]),
    [
      ['sku:12000040000000001', 2],
      ['sku:12000040000000002', 1],
    ],
  );
});

test('exactDate conserva pedidos que reaparecen tras dos páginas antiguas', async () => {
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
        fields: fields('8211744661738042', 'Apr 6, 2026'),
      },
    },
    2: {
      pc_om_list_order_2: {
        fields: fields('8209933206078042', 'Apr 5, 2026'),
      },
    },
    3: {
      pc_om_list_order_3: {
        fields: fields('8209933206078043', 'Apr 4, 2026'),
      },
    },
    4: {
      pc_om_list_order_4: {
        fields: fields('8209933206078044', 'Apr 6, 2026'),
      },
    },
    5: {},
  });

  const result = await bridge.ordersApiCollect({ exactDate: '2026-04-06' });

  assert.equal(result.ok, true);
  assert.deepEqual(
    Array.from(result.orders, (order) => order.orderNumber),
    ['8211744661738042', '8209933206078044'],
  );
  assert.equal(result.pagesRead, 10);
  assert.equal(result.coverage.pageLimit, 60);
  assert.equal(result.coverage.targetDateComplete, true);
  assert.equal(result.termination.kind, 'certified-has-more-false');
  assert.equal(result.termination.naturalExhaustion, true);
  assert.equal(result.certification.certified, true);
  assert.equal(result.certification.passCount, 2);
  assert.deepEqual(Array.from(result.warnings), []);
});

test('reescribe sólo el único pageIndex estructurado de la plantilla', async () => {
  const requests = [];
  const bridge = await installOrdersApiFixture(
    { 1: {} },
    {
      requests,
      templateParams: {
        pageIndex: 1,
        pageSize: 20,
        status: 'all',
        fromDate: '2025-06-01',
        accessToken: 'must-not-leak',
      },
    },
  );

  const probe = await bridge.ordersApiShapeProbe();
  assert.equal(probe.ok, true);
  const rewritten = JSON.parse(bridge._testing.ordersApiParamsForPage(7));
  assert.deepEqual(rewritten, {
    pageIndex: 7,
    pageSize: 20,
    status: 'all',
    fromDate: '2025-06-01',
    accessToken: 'must-not-leak',
  });
  assert.equal(requests.length, 1);
  assert.equal(requests[0].pageIndex, 1);

  const serializedProbe = JSON.stringify(probe);
  assert.match(serializedProbe, /pageIndex/);
  assert.match(serializedProbe, /pageSize/);
  assert.match(serializedProbe, /fromDate/);
  assert.doesNotMatch(serializedProbe, /accessToken|must-not-leak/i);
});

test('rechaza una plantilla con más de un pageIndex', async () => {
  const bridge = await installOrdersApiFixture(
    {},
    { templateParams: { pageIndex: 1, nested: { pageIndex: 2 } } },
  );

  const probe = await bridge.ordersApiShapeProbe();
  assert.equal(probe.ok, false);
  assert.match(probe.reason, /pageIndex único/);
  assert.equal(bridge._testing.ordersApiParamsForPage(3), null);
});

test('reescribe pageIndex dentro de JSON serializado sin tocar otros campos', async () => {
  const nested = JSON.stringify({
    pageIndex: '1',
    pageSize: 50,
    status: 'archived',
  });
  const bridge = await installOrdersApiFixture(
    { undefined: {} },
    {
      templateParams: {
        request: nested,
        signatureToken: 'must-not-leak',
      },
    },
  );

  const probe = await bridge.ordersApiShapeProbe();
  assert.equal(probe.ok, true);
  assert.equal(probe.template.pageIndexSlots, 1);
  assert.equal(probe.template.fields['request.pageIndex'], '1');
  assert.equal(probe.template.fields['request.pageSize'], 50);
  assert.equal(probe.template.fields['request.status'], 'archived');
  const rewritten = JSON.parse(bridge._testing.ordersApiParamsForPage(9));
  assert.deepEqual(JSON.parse(rewritten.request), {
    pageIndex: '9',
    pageSize: 50,
    status: 'archived',
  });
  assert.equal(rewritten.signatureToken, 'must-not-leak');
  assert.doesNotMatch(JSON.stringify(probe), /signatureToken|must-not-leak/i);
});

test('la sonda de respuesta expone metadata y nunca datos de pedidos o secretos', () => {
  const summary = parser.ordersApiResponseSummary({
    accessToken: 'root-secret',
    data: {
      totalCount: 45,
      data: {
        pc_om_list_header_1: {
          fields: {
            searchTimeOptions: [
              { code: 'all', text: 'All time' },
              { code: '2025', text: '2025' },
            ],
            statusTabList: [
              { code: 'all', title: 'All orders' },
              { code: 'archived', title: 'Archived' },
            ],
          },
        },
        pagination: {
          hasNext: true,
          hasMore: true,
          totalPage: 3,
          pageSize: 20,
          token: 'next-page-secret',
        },
        pc_om_list_order_1: {
          fields: {
            orderId: '8211744661738042',
            itemTitle: 'private product title',
          },
        },
      },
    },
  });

  assert.equal(summary.orderModuleCount, 1);
  assert.equal(summary.pagination['data.totalCount'], 45);
  assert.equal(summary.pagination['data.data.pagination.hasNext'], true);
  assert.equal(summary.pagination['data.data.pagination.hasMore'], true);
  assert.equal(summary.pagination['data.data.pagination.totalPage'], 3);
  assert.equal(summary.pagination['data.data.pagination.pageSize'], 20);
  assert.deepEqual(JSON.parse(JSON.stringify(summary.filterOptions.time)), [
    { code: 'all', text: 'All time' },
    { code: '2025', text: '2025' },
  ]);
  assert.deepEqual(JSON.parse(JSON.stringify(summary.filterOptions.status)), [
    { code: 'all', title: 'All orders' },
    { code: 'archived', title: 'Archived' },
  ]);
  const serialized = JSON.stringify(summary);
  assert.doesNotMatch(
    serialized,
    /root-secret|next-page-secret|accessToken|orderId|itemTitle|private product/i,
  );
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

test('exactDate rechaza el resultado parcial al alcanzar maxPages', async () => {
  const bridge = await installOrdersApiFixture({
    1: {
      pc_om_list_order_1: {
        fields: {
          orderId: '8211744661738042',
          orderDateText: 'Jun 15, 2026',
          totalPriceText: 'CLP 10,790',
          currencyCode: 'CLP',
          orderLines: [],
        },
      },
    },
  });

  const result = await bridge.ordersApiCollect({
    exactDate: '2026-06-15',
    maxPages: 1,
  });

  assert.equal(result.ok, false);
  assert.deepEqual(Array.from(result.orders), []);
  assert.equal(result.partialOrderCount, 1);
  assert.equal(result.coverage.targetDateComplete, false);
  assert.equal(result.coverage.partial, true);
  assert.equal(result.termination.kind, 'max-pages');
  assert.equal(result.termination.naturalExhaustion, false);
  assert.equal(result.warnings.length, 1);
  assert.match(result.warnings[0], /No se generó una factura parcial/);
});

test('evaluationOnly expone filas reales sólo como discovery no certificado', async () => {
  const bridge = await installOrdersApiFixture({
    1: {
      pc_om_list_order_1: {
        fields: {
          orderId: '8211744661738042',
          orderDateText: 'Jun 1, 2025',
          totalPriceText: 'CLP 10,790',
          currencyCode: 'CLP',
          orderLines: [],
        },
      },
    },
  });

  const result = await bridge.ordersApiCollect({
    exactDate: '2025-06-01',
    maxPages: 1,
    evaluationOnly: true,
  });

  assert.equal(result.ok, true);
  assert.equal(result.evaluationOnly, true);
  assert.equal(result.orders.length, 1);
  assert.equal(result.coverage.mode, 'discovery-read-only');
  assert.equal(result.coverage.certified, false);
  assert.equal(result.coverage.targetDateComplete, false);
  assert.equal(result.termination.naturalExhaustion, false);
  assert.match(result.warnings[0], /no autoriza guardar, vincular ni crear/);
});

test('evaluationOnly corta tras cinco páginas antiguas sin fingir cobertura', async () => {
  const page = (id, date) => ({
    pc_om_list_order_1: {
      fields: {
        orderId: id,
        orderDateText: date,
        totalPriceText: 'CLP 1,000',
        currencyCode: 'CLP',
        orderLines: [],
      },
    },
  });
  const bridge = await installOrdersApiFixture({
    1: page('target', 'Jun 7, 2025'),
    2: page('older-1', 'Jun 6, 2025'),
    3: page('older-2', 'Jun 5, 2025'),
    4: page('older-3', 'Jun 4, 2025'),
    5: page('older-4', 'Jun 3, 2025'),
    6: page('older-5', 'Jun 2, 2025'),
    7: page('unread', 'Jun 7, 2025'),
  });

  const result = await bridge.ordersApiCollect({
    exactDate: '2025-06-07',
    maxPages: 20,
    evaluationOnly: true,
  });

  assert.equal(result.ok, true);
  assert.equal(result.evaluationOnly, true);
  assert.equal(result.orders.length, 1);
  assert.equal(result.pagesRead, 6);
  assert.equal(result.reason, 'discovery-frontier');
  assert.equal(result.coverage.targetDateComplete, false);
  assert.equal(result.coverage.certified, false);
});

test('exactDate rechaza y advierte si una página de la API falla', async () => {
  const bridge = await installOrdersApiFixture({
    1: {
      pc_om_list_order_1: {
        fields: {
          orderId: '8211744661738042',
          orderDateText: 'Jun 15, 2026',
          totalPriceText: 'CLP 10,790',
          currencyCode: 'CLP',
          orderLines: [],
        },
      },
    },
    2: new Error('network interrupted'),
  });

  const result = await bridge.ordersApiCollect({
    exactDate: '2026-06-15',
    maxPages: 60,
  });

  assert.equal(result.ok, false);
  assert.deepEqual(Array.from(result.orders), []);
  assert.equal(result.partialOrderCount, 1);
  assert.equal(result.coverage.targetDateComplete, false);
  assert.equal(result.termination.kind, 'error');
  assert.equal(result.termination.naturalExhaustion, false);
  assert.equal(result.warnings.length, 1);
  assert.match(result.warnings[0], /error en página 2/);
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
  assert.equal(result.coverage.mode, 'two-pass-target-v2');
  assert.equal(result.coverage.targetDateComplete, true);
  assert.equal(result.coverage.certified, true);
});

test('rechaza una página no terminal corta antes de certificar', async () => {
  const fields = (orderId) => ({
    orderId,
    orderDateText: 'Jun 1, 2025',
    totalPriceText: 'CLP 1,000',
    currencyCode: 'CLP',
    orderLines: [],
  });
  const bridge = await installOrdersApiFixture({
    1: { pc_om_list_order_1: { fields: fields('1001') } },
    2: {
      pc_om_list_order_2: { fields: fields('1002') },
      pc_om_list_order_3: { fields: fields('1003') },
    },
    3: {},
  });

  const result = await bridge.ordersApiCollect({ exactDate: '2025-06-01' });

  assert.equal(result.ok, false);
  assert.equal(result.certification.mismatchCodes[0], 'inconsistent-page-size');
  assert.deepEqual(Array.from(result.orders), []);
});

test('un solapamiento idéntico entre páginas se deduplica y certifica', async () => {
  const fields = (orderId) => ({
    orderId,
    orderDateText: 'Jun 1, 2025',
    totalPriceText: 'CLP 1,000',
    currencyCode: 'CLP',
    orderLines: [],
  });
  const bridge = await installOrdersApiFixture(
    {
      1: {
        pc_om_list_order_1: { fields: fields('1001') },
        pc_om_list_order_2: { fields: fields('1002') },
      },
      2: { pc_om_list_order_3: { fields: fields('1002') } },
    },
    { hasMoreByPage: { 1: true, 2: false } },
  );

  const result = await bridge.ordersApiCollect({ exactDate: '2025-06-01' });

  assert.equal(result.ok, true);
  assert.equal(result.coverage.certified, true);
  assert.equal(result.orders.length, 2);
  assert.ok(result.certification.passes.every(
    (pass) => pass.overlapOrderCount === 1,
  ));
});

test('un orderId repetido con payload distinto aborta como drift real', async () => {
  const fields = (quantity) => ({
    orderId: '1001',
    orderDateText: 'Jun 1, 2025',
    totalPriceText: 'CLP 1,000',
    currencyCode: 'CLP',
    orderLines: [{ productId: 'p1', quantity, formatPriceInfo: 'CLP 1,000' }],
  });
  const bridge = await installOrdersApiFixture(
    {
      1: { pc_om_list_order_1: { fields: fields(1) } },
      2: { pc_om_list_order_2: { fields: fields(2) } },
    },
    { hasMoreByPage: { 1: true, 2: false } },
  );

  const result = await bridge.ordersApiCollect({ exactDate: '2025-06-01' });

  assert.equal(result.ok, false);
  assert.equal(result.certification.mismatchCodes[0], 'duplicate-order-drift');
});

test('una página completa sin pedidos nuevos aborta como paginación estancada', async () => {
  const fields = (orderId) => ({
    orderId,
    orderDateText: 'Jun 1, 2025',
    totalPriceText: 'CLP 1,000',
    currencyCode: 'CLP',
    orderLines: [],
  });
  const bridge = await installOrdersApiFixture(
    {
      1: { pc_om_list_order_1: { fields: fields('1001') } },
      2: { pc_om_list_order_2: { fields: fields('1001') } },
      3: {},
    },
    { hasMoreByPage: { 1: true, 2: true, 3: false } },
  );

  const result = await bridge.ordersApiCollect({ exactDate: '2025-06-01' });

  assert.equal(result.ok, false);
  assert.equal(result.certification.mismatchCodes[0], 'stalled-pagination');
});

test('elige la ventana temporal mínima con margen seguro', () => {
  const now = new Date('2026-08-13T18:00:00Z');
  assert.equal(parser.exactDateTimeOption('2026-08-12', now), '6m');
  assert.equal(parser.exactDateTimeOption('2026-03-01', now), '1y');
  assert.equal(parser.exactDateTimeOption('2025-09-01', now), '2y');
  assert.equal(parser.exactDateTimeOption('2024-01-01', now), 'all');
});

test('dos recorridos con conjuntos distintos nunca se certifican', async () => {
  const fields = (orderId) => ({
    orderId,
    orderDateText: 'Jun 1, 2025',
    totalPriceText: 'CLP 1,000',
    currencyCode: 'CLP',
    orderLines: [],
  });
  const basePages = {
    1: { pc_om_list_order_1: { fields: fields('1001') } },
    2: {},
  };
  const bridge = await installOrdersApiFixture(basePages, {
    pageProvider: ({ pageIndex, requestIndex }) => {
      if (pageIndex === 1 && requestIndex >= 3) {
        return { pc_om_list_order_1: { fields: fields('1002') } };
      }
      return basePages[pageIndex];
    },
  });

  const result = await bridge.ordersApiCollect({ exactDate: '2025-06-01' });

  assert.equal(result.ok, false);
  assert.equal(result.certification.mismatchCodes[0], 'pass-drift');
  assert.deepEqual(Array.from(result.orders), []);
});

test('un eco de filtros distinto aborta sin conservar pedidos', async () => {
  const bridge = await installOrdersApiFixture(
    {
      1: {
        pc_om_list_order_1: {
          fields: {
            orderId: '1001',
            orderDateText: 'Jun 1, 2025',
            totalPriceText: 'CLP 1,000',
            currencyCode: 'CLP',
            orderLines: [],
          },
        },
      },
      2: {},
    },
    { responseStatusByPage: { 1: 'completed' } },
  );

  const result = await bridge.ordersApiCollect({ exactDate: '2025-06-01' });

  assert.equal(result.ok, false);
  assert.equal(result.certification.mismatchCodes[0], 'filter-coerced');
});

test('una primera página vacía no certifica que el día no tenga pedidos', async () => {
  const bridge = await installOrdersApiFixture({ 1: {} });

  const result = await bridge.ordersApiCollect({ exactDate: '2025-06-01' });

  assert.equal(result.ok, false);
  assert.equal(
    result.certification.mismatchCodes[0],
    'unavailable-empty-first-page',
  );
});

test('la sonda recycle reescribe sólo statusTab y no devuelve pedidos', async () => {
  const requests = [];
  const bridge = await installOrdersApiFixture(
    {
      1: {
        pc_om_list_order_1: {
          fields: {
            orderId: '1001',
            orderDateText: 'Jun 1, 2025',
            totalPriceText: 'CLP 1,000',
            currencyCode: 'CLP',
            orderLines: [],
          },
        },
      },
      2: {},
    },
    { requests },
  );

  const result = await bridge.ordersApiScopeProbe({
    exactDate: '2025-06-01',
    statusTab: 'recycle',
  });

  assert.equal(result.ok, true);
  assert.equal(result.targetDateCount, 1);
  assert.equal(result.scope.statusTab, 'recycle');
  assert.ok(requests.every((request) => request.statusTab === 'recycle'));
  assert.equal(Object.prototype.hasOwnProperty.call(result, 'orders'), false);
});
