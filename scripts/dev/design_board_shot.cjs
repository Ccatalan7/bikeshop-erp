#!/usr/bin/env node
// Draws one artboard of a Claude Design canvas (`project/<name>.dc.html`) to a
// PNG without opening the canvas: runs its `renderVals()` with the given props
// and expands `{{holes}}`, `<sc-if>` and `<sc-for>` the way the canvas does.
// `<dc-import>` is not supported: draw the child board on its own.
//
//   node scripts/dev/design_board_shot.cjs <board.dc.html> <out.png> <w> <h> \
//     [--props '{"dark":true}'] [--mobile] [--blob <32-hex id>=<local file>]...
//
// An uploaded image is `/_blob/<id>` in the board; pass the local file it came
// from with --blob or it draws empty. The PNG is the first <w>×<h> at 2×.
const fs = require('fs');
const path = require('path');
const { chromium } = require(path.join(__dirname, '..', '..', 'node_modules', 'playwright-core'));

const args = process.argv.slice(2);
const [file, out, width, height] = args;
if (!file || !out || !width || !height) {
  console.error('usage: design_board_shot.cjs <board.dc.html> <out.png> <w> <h> [--props json] [--mobile] [--blob id=file]');
  process.exit(2);
}
let props = {};
let mobile = false;
const blobs = {};
for (let i = 4; i < args.length; i++) {
  if (args[i] === '--props') props = JSON.parse(args[++i]);
  else if (args[i] === '--mobile') mobile = true;
  else if (args[i] === '--blob') {
    const [id, source] = args[++i].split('=');
    blobs[id] = path.resolve(source);
  }
}

(async () => {
  const html = fs.readFileSync(file, 'utf8');
  const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  const page = await browser.newPage({ viewport: { width: +width, height: +height }, deviceScaleFactor: 2, isMobile: mobile });
  // A viewport meta, or a phone board is laid out at 980 px.
  await page.route('http://canvas.local/**', async (route) => {
    const match = new URL(route.request().url()).pathname.match(/^\/_blob\/([0-9a-f]{32})/);
    if (match) {
      if (!blobs[match[1]]) return route.fulfill({ status: 404, body: '' });
      return route.fulfill({ path: blobs[match[1]] });
    }
    return route.fulfill({ contentType: 'text/html', body: '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body></body></html>' });
  });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('http://canvas.local/');
  const drawnHeight = await page.evaluate(({ source, boardProps }) => {
    const doc = new DOMParser().parseFromString(source, 'text/html');
    const script = doc.querySelector('script[data-dc-script]').textContent;
    class DCLogic {
      constructor(p) { this.props = p || {}; this.state = {}; }
      setState() {}
      forceUpdate() {}
    }
    const Component = new Function('DCLogic', `${script}\n;return Component;`)(DCLogic);
    const vals = new Component(boardProps).renderVals();
    const lookup = (scope, p) => p.trim().split('.').reduce((o, k) => (o == null ? undefined : o[k]), scope);
    const value = (scope, p) => {
      const t = p.trim();
      if (t === 'true') return true;
      if (t === 'false') return false;
      return lookup(scope, t);
    };
    // Text keeps its own spaces: «Pidió: {{x}}» must not glue together.
    const interpolate = (s, scope) => s.replace(/\{\{([^}]*)\}\}/g, (_, p) => {
      const v = value(scope, p);
      return v == null ? '' : String(v);
    });
    const whole = /^\s*\{\{([^}]*)\}\}\s*$/;
    function render(node, scope, parent) {
      if (node.nodeType === 3) {
        parent.appendChild(document.createTextNode(interpolate(node.textContent, scope)));
        return;
      }
      if (node.nodeType !== 1) return;
      const tag = node.tagName.toLowerCase();
      if (tag === 'helmet') {
        for (const child of node.childNodes) render(child, scope, document.head);
        return;
      }
      if (tag === 'sc-if') {
        if (value(scope, node.getAttribute('value').match(whole)[1])) {
          for (const child of node.childNodes) render(child, scope, parent);
        }
        return;
      }
      if (tag === 'sc-for') {
        const list = value(scope, node.getAttribute('list').match(whole)[1]) || [];
        const as = node.getAttribute('as');
        list.forEach((item, index) => {
          for (const child of node.childNodes) render(child, { ...scope, [as]: item, $index: index }, parent);
        });
        return;
      }
      const el = node.namespaceURI === 'http://www.w3.org/2000/svg'
        ? document.createElementNS(node.namespaceURI, node.tagName)
        : document.createElement(tag);
      for (const attribute of node.attributes) {
        const match = attribute.value.match(whole);
        if (!match) {
          el.setAttribute(attribute.name, attribute.value.includes('{{') ? interpolate(attribute.value, scope) : attribute.value);
          continue;
        }
        const v = value(scope, match[1]);
        if (typeof v === 'function') continue; // an event handler
        if (v === false || v == null) {
          if (attribute.name.startsWith('aria-')) el.setAttribute(attribute.name, 'false');
          continue;
        }
        el.setAttribute(attribute.name, String(v));
      }
      for (const child of node.childNodes) render(child, scope, el);
      parent.appendChild(el);
    }
    for (const child of doc.querySelector('x-dc').childNodes) render(child, vals, document.body);
    return document.body.scrollHeight;
  }, { source: html, boardProps: props });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: out, clip: { x: 0, y: 0, width: +width, height: +height } });
  console.log(`ok ${out} (content ${drawnHeight}px tall)${errors.length ? ` errors: ${errors.join(' | ')}` : ''}`);
  await browser.close();
})();
