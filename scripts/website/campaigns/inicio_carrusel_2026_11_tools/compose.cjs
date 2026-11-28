#!/usr/bin/env node
// compose.cjs [name...] — from each frame's ground art (F whole, G without
// what must not repeat): the center image with 30 px more at the foot, and a
// bleed for each side (the ground mirrored at the seam: sharp for the first
// `safe` px, then out of focus, ending in one flat color the far band takes).
const fs = require('fs');
const path = require('path');
const { chromium } = require(require('path').resolve(__dirname, '../../../../node_modules/playwright-core'));
// The working folder: frames/, meas/, art/, out/ and src/ live in it.
const S = process.env.CAMPAIGN_WORK || process.cwd();
const NAMES = ['lovasquez', 'ninos', 'servicios', 'maxxis', 'horquillas', 'cassette', 'accesorios'];
// How far from each edge the desktop ground has nothing that reads as an
// object when mirrored (a wheel, a diagonal): [left, right].
const SAFE = { lovasquez: [380, 560], ninos: [500, 560], servicios: [270, 560], maxxis: [560, 560], horquillas: [560, 560], cassette: [560, 560], accesorios: [560, 560] };
const FOOT = 30;
const only = process.argv.slice(2);

function gb(file, w) {
  // the ground with its foot mirrored under it: w × (750 + FOOT)
  return `<div style="position:absolute;left:0;top:0;width:${w}px;height:${750 + FOOT}px;overflow:hidden">
<img src="file://${file}" style="position:absolute;left:0;top:0;width:${w}px;height:750px">
<div style="position:absolute;left:0;top:750px;width:${w}px;height:${FOOT}px;overflow:hidden"><img src="file://${file}" style="position:absolute;left:0;top:0;width:${w}px;height:750px;transform:scaleY(-1)"></div></div>`;
}

function bleedHtml(file, w, B, side, safe, blur, far, ramp) {
  const H = 750 + FOOT;
  // the mirrored ground, its seam on the inner edge of the bleed
  const mirrored = `<div style="position:absolute;${side === 'left' ? `right:0` : `left:0`};top:0;width:${w}px;height:${H}px;transform:scaleX(-1)">${gb(file, w)}</div>`;
  // and the ground itself past the seam, so the blur has something to read
  const beyond = `<div style="position:absolute;${side === 'left' ? `left:${B}px` : `left:${-w}px`};top:0;width:${w}px;height:${H}px">${gb(file, w)}</div>`;
  const dir = side === 'left' ? 'to left' : 'to right';
  const fade = far ? `<div style="position:absolute;inset:0;background:linear-gradient(${dir},rgb(0 0 0 / 0) ${B - 170}px,${far} ${B - 10}px)"></div>` : '';
  return `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:#000}</style></head><body>
<div id="b" style="position:relative;width:${B}px;height:${H}px;overflow:hidden">
<div style="position:absolute;inset:0;filter:blur(${blur}px);transform:scaleY(1.16)">${mirrored}${beyond}</div>
<div style="position:absolute;inset:0;-webkit-mask-image:linear-gradient(${dir},#000 0,#000 ${safe}px,transparent ${safe + ramp}px);mask-image:linear-gradient(${dir},#000 0,#000 ${safe}px,transparent ${safe + ramp}px)">${mirrored}</div>
${fade}</div></body></html>`;
}

(async () => {
  const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: ['--allow-file-access-from-files'] });
  const colors = fs.existsSync(path.join(S, 'out', 'far.json')) ? JSON.parse(fs.readFileSync(path.join(S, 'out', 'far.json'), 'utf8')) : {};
  try {
    for (const name of NAMES) {
      if (only.length && !only.includes(name)) continue;
      for (const v of ['d', 'm']) {
        const w = v === 'd' ? 1440 : 390;
        const B = v === 'd' ? 560 : 255;
        const F = path.join(S, 'art', `${name}-${v}-F.png`);
        const G = path.join(S, 'art', `${name}-${v}-G.png`);
        // center, 2×
        let page = await browser.newPage({ viewport: { width: w, height: 750 + FOOT }, deviceScaleFactor: 2 });
        await page.setContent(`<!doctype html><html><head><style>html,body{margin:0;background:#000}</style></head><body>${gb(F, w)}</body></html>`, { waitUntil: 'load' });
        // a file page may not read file images from about:blank: load through a real file
        const tmp = path.join(S, 'out', `_tmp-${name}-${v}.html`);
        fs.writeFileSync(tmp, `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:#000}</style></head><body>${gb(F, w)}</body></html>`);
        await page.goto('file://' + tmp, { waitUntil: 'load' });
        await page.evaluate(() => Promise.all([...document.images].map((i) => i.decode().catch(() => {}))));
        await page.screenshot({ path: path.join(S, 'out', `${name}-${v}-center.png`), clip: { x: 0, y: 0, width: w, height: 750 + FOOT } });
        await page.close();
        for (const side of ['left', 'right']) {
          // A narrow composition has objects right at its edges: its bleed
          // goes out of focus at once and needs no far band (255 covers a
          // tablet).
          const safe = v === 'd' ? SAFE[name][side === 'left' ? 0 : 1] : 0;
          const blur = v === 'd' ? 34 : 38;
          const ramp = v === 'd' ? 90 : 30;
          const key = `${name}-${v}-${side}`;
          for (const pass of [0, 1]) {
            page = await browser.newPage({ viewport: { width: B, height: 750 + FOOT }, deviceScaleFactor: 1 });
            fs.writeFileSync(tmp, bleedHtml(G, w, B, side, Math.min(safe, B - 100), blur, pass && v === 'd' ? colors[key] : null, ramp));
            await page.goto('file://' + tmp, { waitUntil: 'load' });
            await page.evaluate(() => Promise.all([...document.images].map((i) => i.decode().catch(() => {}))));
            const file = path.join(S, 'out', `${key}.png`);
            await page.screenshot({ path: file, clip: { x: 0, y: 0, width: B, height: 750 + FOOT } });
            if (!pass) {
              // the flat color the far band takes: the mean of the outer edge
              colors[key] = await page.evaluate(async ({ file, side, B }) => {
                const img = new Image(); img.src = 'file://' + file + '?' + Date.now(); await img.decode();
                const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
                const g = c.getContext('2d'); g.drawImage(img, 0, 0);
                const x0 = side === 'left' ? 0 : B - 12;
                const d = g.getImageData(x0, 0, 12, img.height).data;
                let r = 0, gg = 0, b = 0, n = d.length / 4;
                for (let i = 0; i < d.length; i += 4) { r += d[i]; gg += d[i + 1]; b += d[i + 2]; }
                const h = (v) => Math.round(v / n).toString(16).padStart(2, '0');
                return '#' + h(r) + h(gg) + h(b);
              }, { file, side, B });
            }
            await page.close();
          }
        }
        fs.unlinkSync(tmp);
        console.log(name, v, colors[`${name}-${v}-left`], colors[`${name}-${v}-right`]);
      }
    }
    fs.writeFileSync(path.join(S, 'out', 'far.json'), JSON.stringify(colors, null, 1));
  } finally {
    await browser.close();
  }
})().catch((e) => { console.error(e); process.exit(1); });
