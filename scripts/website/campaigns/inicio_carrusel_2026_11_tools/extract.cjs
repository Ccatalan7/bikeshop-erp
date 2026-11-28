#!/usr/bin/env node
// extract.cjs [name...] — for each approved frame: measures the texts, buttons,
// links, product images and accents that become editor layers, then draws the
// ground art with those hidden (F: the whole ground; G: without what must not
// be mirrored into the bleed).
const fs = require('fs');
const path = require('path');
const { chromium } = require(require('path').resolve(__dirname, '../../../../node_modules/playwright-core'));

// The working folder: frames/, meas/, art/, out/ and src/ live in it.
const S = process.env.CAMPAIGN_WORK || process.cwd();
const NAMES = ['lovasquez', 'ninos', 'servicios', 'maxxis', 'horquillas', 'cassette', 'accesorios'];
// What the mirrored bleed must not repeat: the drawn numbers and labels.
const CENTER_ONLY = {
  lovasquez: ['.dawn .n', '.dawn .km', '.dawn .lb', '.dawn .dot', '.dawn .ld', '.dawn .halo'],
  ninos: ['.big'],
  horquillas: ['.stack', '.halo'],
};
const only = process.argv.slice(2);

function measure() {
  const frame = document.querySelector('.vb');
  const fr = frame.getBoundingClientRect();
  const R = (r) => ({ x: +(r.left - fr.left).toFixed(2), y: +(r.top - fr.top).toFixed(2), w: +r.width.toFixed(2), h: +r.height.toFixed(2) });
  const hex = (c) => {
    const m = c.match(/rgba?\(([^)]+)\)/);
    if (!m) return c;
    const p = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number);
    const a = p.length > 3 ? Math.round(p[3] * 255) : 255;
    const h2 = (v) => Math.round(v).toString(16).padStart(2, '0').toUpperCase();
    return '#' + (a < 255 ? h2(a) : '') + h2(p[0]) + h2(p[1]) + h2(p[2]);
  };
  const out = { frame: { w: fr.width, h: fr.height }, texts: [], buttons: [], images: [], shapes: [] };
  const TEXT_SEL = '.eye,.ttl,.sub,.fine,.tag,.spec,.sign,.pn,.pp,.pd,.price';
  const containers = [...frame.querySelectorAll(TEXT_SEL)].filter((e) => !e.closest('.btn'));

  // 1. the weight each text was designed in, before the site's own drawing of
  //    its heading font replaces it (400, with a stroke from 600 up).
  const intended = new Map();
  const styled = new Set();
  for (const c of containers) for (const e of [c, ...c.querySelectorAll('*')]) styled.add(e);
  for (const e of styled) intended.set(e, +getComputedStyle(e).fontWeight);
  for (const e of styled) {
    const cs = getComputedStyle(e);
    if (/^"?Oswald/.test(cs.fontFamily)) {
      e.style.fontWeight = '400';
      e.style.webkitTextStroke = intended.get(e) >= 600 ? '.032em currentColor' : '0';
    }
  }
  // 2. titles are measured upright; the layer leans them again.
  for (const e of frame.querySelectorAll('.ttl')) e.style.transform = 'none';

  const icon = (el) => {
    const d = el.querySelector('svg path')?.getAttribute('d') || '';
    if (d.startsWith('M12.04 2')) return 'whatsapp';
    if (d.startsWith('M5 12h14')) return 'arrow';
    return null;
  };
  // 3. buttons and links
  for (const b of frame.querySelectorAll('.btn')) {
    const cs = getComputedStyle(b);
    out.buttons.push({ kind: 'button', ...R(b.getBoundingClientRect()), label: b.textContent.trim(), href: b.getAttribute('href'),
      bg: hex(cs.backgroundColor), fg: hex(cs.color), radius: parseFloat(cs.borderTopLeftRadius), fontSize: parseFloat(cs.fontSize),
      weight: +cs.fontWeight, icon: icon(b), cls: b.className });
  }
  for (const a of frame.querySelectorAll('.lnk')) {
    const cs = getComputedStyle(a);
    // the words and glyph themselves: a link stretched across its row is
    // still as wide as what it says
    const tight = document.createRange(); tight.selectNodeContents(a);
    const tr = tight.getBoundingClientRect(), ar = a.getBoundingClientRect();
    const box = { left: tr.left, top: ar.top, width: tr.width, height: ar.height };
    out.buttons.push({ kind: 'link', ...R(box), label: a.textContent.trim(), href: a.getAttribute('href'),
      fg: hex(cs.color), fontSize: parseFloat(cs.fontSize), weight: +cs.fontWeight, icon: icon(a), cls: a.className,
      inTag: !!a.closest('.tag') });
  }
  // 4. text, one fragment per run of one style on one line
  const range = document.createRange();
  for (const c of containers) {
    const walker = document.createTreeWalker(c, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (!node.data.trim()) continue;
      const parent = node.parentElement;
      if (parent.closest('.lnk') || parent.closest('svg')) continue;
      const cs = getComputedStyle(parent);
      const s = node.data;
      const runs = [];
      let start = -1, lastTop = null;
      for (let i = 0; i < s.length; i++) {
        if (/\s/.test(s[i])) continue;
        range.setStart(node, i); range.setEnd(node, i + 1);
        const rc = range.getClientRects()[0];
        if (!rc) continue;
        if (start < 0) { start = i; lastTop = rc.top; continue; }
        if (Math.abs(rc.top - lastTop) > rc.height / 2) { runs.push([start, i]); start = i; lastTop = rc.top; }
      }
      if (start >= 0) runs.push([start, s.length]);
      for (const [a, b] of runs) {
        range.setStart(node, a); range.setEnd(node, b);
        const text = s.slice(a, b).replace(/\s+/g, ' ').trim();
        if (!text) continue;
        const fs = parseFloat(cs.fontSize);
        const lh = cs.lineHeight === 'normal' ? fs * 1.2 : parseFloat(cs.lineHeight);
        out.texts.push({ ...R(range.getBoundingClientRect()), text, container: c.className, parent: parent.className || parent.tagName.toLowerCase(),
          sameParent: parent === c, fontSize: fs, lineHeight: +(lh / fs).toFixed(4), weight: intended.get(parent),
          heading: /^"?Oswald/.test(cs.fontFamily), color: hex(cs.color), letterSpacing: cs.letterSpacing === 'normal' ? 0 : parseFloat(cs.letterSpacing),
          uppercase: cs.textTransform === 'uppercase', skew: c.classList.contains('ttl') ? -8 : 0, align: cs.textAlign });
      }
    }
  }
  // 5. product images and marks, upright
  for (const im of frame.querySelectorAll('img.bk,img.fk,img.cs,img.ty,img.pr,img.mxl')) {
    const t = getComputedStyle(im).transform;
    let rot = 0;
    if (t && t !== 'none') { const m = t.match(/matrix\(([^)]+)\)/); if (m) { const v = m[1].split(',').map(Number); rot = Math.round(Math.atan2(v[1], v[0]) * 180 / Math.PI); } }
    const keep = im.style.transform; im.style.transform = 'none';
    out.images.push({ ...R(im.getBoundingClientRect()), src: im.getAttribute('src'), alt: im.getAttribute('alt'), cls: im.className, rotation: rot,
      clip: im.closest('.pane') ? getComputedStyle(im.closest('.pane')).clipPath : null });
    im.style.transform = keep;
  }
  // 6. accents that stay editable shapes
  for (const s of frame.querySelectorAll('.sign')) {
    out.shapes.push({ kind: 'sign', ...R(s.getBoundingClientRect()), fill: hex(getComputedStyle(s).backgroundColor), radius: parseFloat(getComputedStyle(s).borderTopLeftRadius) });
  }
  for (const s of frame.querySelectorAll('.bar-r')) out.shapes.push({ kind: 'bar', ...R(s.getBoundingClientRect()), fill: hex(getComputedStyle(s).backgroundColor) });
  for (const s of frame.querySelectorAll('.s1 .pp')) {
    const r = R(s.getBoundingClientRect());
    out.shapes.push({ kind: 'marker', x: r.x, y: +(r.y + r.h * 0.64).toFixed(2), w: r.w, h: +(r.h * 0.30).toFixed(2), fill: '#FFC61A' });
  }
  const plans = [...frame.querySelectorAll('.plan')];
  plans.forEach((p, i) => {
    const r = R(p.getBoundingClientRect());
    const cs = getComputedStyle(p);
    out.shapes.push({ kind: 'rule', x: r.x, y: r.y, w: r.w, h: 1, fill: hex(cs.borderTopColor) });
    if (i === plans.length - 1) out.shapes.push({ kind: 'rule', x: r.x, y: +(r.y + r.h - 1).toFixed(2), w: r.w, h: 1, fill: hex(cs.borderBottomColor) });
  });
  // 7. what became a layer leaves the art
  for (const e of [...containers, ...frame.querySelectorAll('.btn,.lnk,img.bk,img.fk,img.cs,img.ty,img.pr,img.mxl,.bar-r')]) e.style.visibility = 'hidden';
  for (const p of plans) p.style.borderColor = 'transparent';
  return out;
}

(async () => {
  const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  try {
    for (const name of NAMES) {
      if (only.length && !only.includes(name)) continue;
      for (const v of ['d', 'm']) {
        const w = v === 'd' ? 1440 : 390;
        const page = await browser.newPage({ viewport: { width: w, height: 750 }, deviceScaleFactor: 2 });
        await page.goto('file://' + path.join(S, 'frames', `${name}-${v}.html`), { waitUntil: 'load' });
        await page.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map((i) => i.decode().catch(() => {}))); });
        await page.screenshot({ path: path.join(S, 'art', `${name}-${v}-ref.png`), clip: { x: 0, y: 0, width: w, height: 750 } });
        const data = await page.evaluate(measure);
        fs.writeFileSync(path.join(S, 'meas', `${name}-${v}.json`), JSON.stringify(data, null, 1));
        await page.screenshot({ path: path.join(S, 'art', `${name}-${v}-F.png`), clip: { x: 0, y: 0, width: w, height: 750 } });
        const hide = [...(CENTER_ONLY[name] || []), ...(v === 'm' ? ['.dawn .n', '.dawn .km', '.dawn .lb', '.dawn .dot', '.dawn .ld', '.big', '.stack', '.halo', '.gh', '.gr'] : [])];
        if (hide.length) await page.evaluate((sel) => { for (const e of document.querySelectorAll(sel.join(','))) e.style.visibility = 'hidden'; }, hide);
        await page.screenshot({ path: path.join(S, 'art', `${name}-${v}-G.png`), clip: { x: 0, y: 0, width: w, height: 750 } });
        console.log(name, v, 'texts', data.texts.length, 'buttons', data.buttons.length, 'images', data.images.length, 'shapes', data.shapes.length);
        await page.close();
      }
    }
  } finally {
    await browser.close();
  }
})().catch((e) => { console.error(e); process.exit(1); });
