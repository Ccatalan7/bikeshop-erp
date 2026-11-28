#!/usr/bin/env node
// alpha.cjs — the catalog and distributor photos as cut-outs: the white
// ground becomes transparent (what `multiply` showed over a light ground),
// so each product is its own layer over any ground.
const fs = require('fs');
const path = require('path');
const { chromium } = require(require('path').resolve(__dirname, '../../../../node_modules/playwright-core'));
// The working folder: frames/, meas/, art/, out/ and src/ live in it.
const S = process.env.CAMPAIGN_WORK || process.cwd();
const frame2img = (rect, pts) => pts.map(([x, y]) => [(x - rect[0]) / rect[2], (y - rect[1]) / rect[3]]);
const JOBS = [
  { out: 'bici-freestyle-16-roja', src: S + '/src/bikes/ROB00005-1.jpg', w: 1400, inset: 0.006 },
  { out: 'cassette-xs-1270', src: S + '/src/mkr-srm00315.png', w: 1350 },
  // the tyre shows through the bone pane only: its diagonal is cut into the photo
  { out: 'neumatico-assegai-d', src: S + '/src/mx-assegai.jpg', w: 894, clip: frame2img([-3, -83, 742, 830], [[0, -90], [878.4, -90], [878.4, 0], [712.8, 750], [0, 750]]) },
  { out: 'neumatico-assegai-m', src: S + '/src/mx-assegai.jpg', w: 800, clip: frame2img([-6, 300, 400, 447], [[-10, 376.5], [400, 313.4], [400, 760], [-10, 760]]) },
  { out: 'candado-espiral-onguard', src: S + '/src/coil-yellow.jpg', w: 500 },
  { out: 'luz-trasera', src: S + '/src/AE0253.png', w: 321 },
  { out: 'bombin-giyo', src: S + '/src/180GP46L.png', w: 444 },
];
(async () => {
  const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: ['--allow-file-access-from-files'] });
  try {
    const page = await browser.newPage();
    const host = path.join(S, 'out', '_alpha.html');
    fs.writeFileSync(host, '<!doctype html><html><body></body></html>');
    await page.goto('file://' + host);
    for (const job of JOBS) {
      const data = await page.evaluate(async (job) => {
        const img = new Image(); img.src = 'file://' + job.src; await img.decode();
        const w = Math.min(job.w, img.naturalWidth), h = Math.round(w * img.naturalHeight / img.naturalWidth);
        const c = document.createElement('canvas'); c.width = w; c.height = h;
        const g = c.getContext('2d'); g.imageSmoothingQuality = 'high';
        // a photo that already has transparency sits on white first
        g.fillStyle = '#fff'; g.fillRect(0, 0, w, h); g.drawImage(img, 0, 0, w, h);
        const id = g.getImageData(0, 0, w, h), d = id.data;
        const inset = Math.round((job.inset || 0) * w);
        const poly = job.clip ? job.clip.map(([u, v]) => [u * w, v * h]) : null;
        const inside = (x, y) => { let s = false; for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) { const [xi, yi] = poly[i], [xj, yj] = poly[j]; if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) s = !s; } return s; };
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
          const i = (y * w + x) * 4;
          let a = 1 - Math.min(d[i], d[i + 1], d[i + 2]) / 255;
          if (a < 0.03 || x < inset || y < inset || x >= w - inset || y >= h - inset || (poly && !inside(x + 0.5, y + 0.5))) a = 0;
          if (a > 0) for (let k = 0; k < 3; k++) d[i + k] = Math.max(0, Math.min(255, Math.round((d[i + k] - 255 * (1 - a)) / a)));
          d[i + 3] = Math.round(a * 255);
        }
        g.putImageData(id, 0, 0);
        return [c.toDataURL('image/png'), w, h];
      }, job);
      fs.writeFileSync(path.join(S, 'out', job.out + '.png'), Buffer.from(data[0].split(',')[1], 'base64'));
      console.log(job.out, data[1], data[2]);
    }
    fs.unlinkSync(host);
  } finally { await browser.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
