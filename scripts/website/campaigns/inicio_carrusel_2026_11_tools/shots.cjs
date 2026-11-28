#!/usr/bin/env node
// shots.cjs <url> <out-prefix> <width>[,<width>...] [slide,...] — the home
// carousel as a visitor sees it at each width, one PNG per slide (header
// included: it sits over the slide).
const { chromium } = require(require('path').resolve(__dirname, '../../../../node_modules/playwright-core'));
const [url, prefix, widths, only] = process.argv.slice(2);
(async () => {
  const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  try {
    for (const w of widths.split(',').map(Number)) {
      const phone = w < 600;
      const ctx = await browser.newContext({ viewport: { width: w, height: phone ? 844 : 900 }, deviceScaleFactor: phone ? 2 : 1, isMobile: phone, hasTouch: phone, reducedMotion: 'reduce' });
      await ctx.route(/(google-analytics\.com|googletagmanager\.com|analytics\.google\.com|connect\.facebook\.net|facebook\.com\/tr)/, (r) => r.abort());
      const page = await ctx.newPage();
      const errors = [];
      page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
      await page.goto(url, { waitUntil: 'load' });
      const car = page.locator('[data-car]').first();
      const n = await car.locator(':scope > .car-slide').count();
      const list = only ? only.split(',').map(Number) : [...Array(n).keys()];
      for (const i of list) {
        await car.evaluate((c, i) => c.dispatchEvent(new CustomEvent('car:go', { detail: i })), i);
        await page.waitForFunction((i) => document.querySelector('[data-car] > .car-slide.on')?.dataset.slide === String(i), i, { timeout: 15000 });
        await page.evaluate(() => Promise.race([new Promise((r) => setTimeout(r, 6000)), Promise.all([...document.querySelectorAll('[data-car] > .car-slide.on img')].filter((m) => m.offsetParent).map((m) => { m.loading = 'eager'; return m.decode ? m.decode().catch(() => {}) : 0; }))]));
        await page.waitForTimeout(450);
        const box = await page.locator('[data-block="carousel"]').first().boundingBox();
        await page.screenshot({ path: `${prefix}-${w}-${i + 1}.png`, clip: { x: 0, y: 0, width: w, height: Math.ceil(box.y + box.height) } });
      }
      const box = await page.locator('[data-block="carousel"]').first().boundingBox();
      console.log(w, 'slides', n, 'block', Math.round(box.width) + 'x' + Math.round(box.height), errors.length ? 'errors: ' + errors.slice(0, 3).join(' | ') : '');
      await ctx.close();
    }
  } finally { await browser.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
