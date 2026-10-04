// Mide una página como la vería un celular lento (mismo método que la página
// instantánea del 24-sep): 1,6 Mbps, 150 ms, CPU ×4, 412×823, perfil nuevo
// por carga. Uso: node measure.mjs <url> <etiqueta> [cargas]
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../package.json', import.meta.url));
const { chromium } = require('playwright-core');

const [url, label, runsArg] = process.argv.slice(2);
const runs = Number(runsArg ?? 3);
const results = [];
for (let i = 0; i < runs; i++) {
  const browser = await chromium.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
  });
  const context = await browser.newContext({
    viewport: { width: 412, height: 823 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
    userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Mobile Safari/537.36',
  });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  await cdp.send('Network.emulateNetworkConditions', {
    offline: false, latency: 150, downloadThroughput: 1.6 * 1024 * 1024 / 8, uploadThroughput: 750 * 1024 / 8,
  });
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  let bytes = 0;
  cdp.on('Network.loadingFinished', (e) => { bytes += e.encodedDataLength; });
  await page.addInitScript(() => {
    window.__lcp = 0;
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) window.__lcp = entry.startTime;
    }).observe({ type: 'largest-contentful-paint', buffered: true });
  });
  const start = Date.now();
  await page.goto(url, { waitUntil: 'load', timeout: 120000 });
  const loadMs = Date.now() - start;
  // Página lista: en la tienda Flutter, cuando retira la instantánea y dibuja
  // la suya; en HTML, la carga misma.
  let readyMs = loadMs;
  const isFlutter = await page.evaluate(() => !!document.querySelector('#instant-page-template, script[src*="flutter"], flutter-view, flt-glass-pane'));
  if (isFlutter) {
    await page.waitForFunction(
      () => !!document.querySelector('flutter-view, flt-glass-pane') && !document.querySelector('#instant-page'),
      null, { timeout: 120000, polling: 250 });
    readyMs = Date.now() - start;
  }
  await page.waitForTimeout(1500);
  const paint = await page.evaluate(() => ({
    fcp: performance.getEntriesByName('first-contentful-paint')[0]?.startTime ?? 0,
    lcp: window.__lcp,
    ttfb: performance.getEntriesByType('navigation')[0]?.responseStart ?? 0,
  }));
  results.push({ ttfb: paint.ttfb, fcp: paint.fcp, lcp: paint.lcp, ready: readyMs, kb: bytes / 1024 });
  await browser.close();
}
const median = (k) => results.map((r) => r[k]).sort((a, b) => a - b)[Math.floor(results.length / 2)];
console.log(JSON.stringify({
  label, runs,
  ttfb_s: +(median('ttfb') / 1000).toFixed(2),
  fcp_s: +(median('fcp') / 1000).toFixed(2),
  lcp_s: +(median('lcp') / 1000).toFixed(2),
  ready_s: +(median('ready') / 1000).toFixed(1),
  transferred_kb: Math.round(median('kb')),
}));
