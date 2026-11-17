// Captura una página entera como la ve una persona, para mostrar un cambio
// de la tienda (local o vinabike.cl) con su imagen real. El panel del
// navegador recorta a un tamaño emulado, `sips --cropOffset` no corta desde
// arriba y un iframe de la tienda queda bloqueado, por eso existe esto.
// Uso: node capture.mjs <url> <ancho> <salida.png> [escala] [alto-de-parte]
// Guarda la página entera y, con alto de parte, también <salida>-1.png,
// -2.png… para revisarla por partes. Bloquea Analytics y el píxel de Meta
// (una captura no es un visitante, como en measure.mjs) y recorre la página
// antes, para que carguen las fotos con loading="lazy".
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../package.json', import.meta.url));
const { chromium } = require('playwright-core');

const [url, widthArg, out, scaleArg = '1', partArg] = process.argv.slice(2);
if (!url || !widthArg || !out?.endsWith('.png')) {
  console.error(
    'Uso: node capture.mjs <url> <ancho> <salida.png> [escala] [alto-de-parte]',
  );
  process.exit(2);
}
const width = Number(widthArg);
const phone = width < 600;
const browser = await chromium.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
const context = await browser.newContext({
  viewport: { width, height: 900 },
  deviceScaleFactor: Number(scaleArg),
  isMobile: phone,
  hasTouch: phone,
});
await context.route(
  /(google-analytics\.com|googletagmanager\.com|analytics\.google\.com|connect\.facebook\.net|facebook\.com\/tr)/,
  (route) => route.abort(),
);
const page = await context.newPage();
await page.goto(url, { waitUntil: 'load' });
await page.evaluate(async () => {
  for (let y = 0; y < document.documentElement.scrollHeight; y += 600) {
    window.scrollTo(0, y);
    await new Promise((resolve) => setTimeout(resolve, 80));
  }
  window.scrollTo(0, 0);
  await document.fonts.ready;
  // Recorrer sólo pide las fotos lazy: hay que esperar a que terminen de
  // bajar, o salen a medias (2026-11-17: la primera foto de /guias salió
  // cortada y las otras cuatro vacías). Como mucho 15 s.
  await Promise.race([
    Promise.all(
      [...document.images].map((image) =>
        image.complete
          ? null
          : new Promise((resolve) => {
              image.addEventListener('load', resolve, { once: true });
              image.addEventListener('error', resolve, { once: true });
            }),
      ),
    ),
    new Promise((resolve) => setTimeout(resolve, 15000)),
  ]);
});
await page.waitForTimeout(500);
await page.screenshot({ path: out, fullPage: true });
const height = await page.evaluate(() => document.documentElement.scrollHeight);
let parts = 0;
if (partArg) {
  const part = Number(partArg);
  for (let y = 0; y < height; y += part) {
    parts += 1;
    await page.screenshot({
      path: out.replace(/\.png$/, `-${parts}.png`),
      fullPage: true,
      clip: { x: 0, y, width, height: Math.min(part, height - y) },
    });
  }
}
console.log(`${out}: ${width}×${height}${parts ? `, ${parts} partes` : ''}`);
await browser.close();
