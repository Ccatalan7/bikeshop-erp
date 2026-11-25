#!/usr/bin/env node
// Small pixel repairs on a PNG, with nothing installed: this Mac has neither
// PIL nor ImageMagick, and paying for another image generation to fix one
// letter also redraws (and degrades) the product. Three commands:
//
//   runs  <png> <y0> <y1> <x0> <x1> [dark|light] [threshold]
//         Lists the glyphs found in a band of rows: the x range of each run of
//         ink columns and its vertical extent. Use it to measure a headline.
//   copy  <in> <out> <srcX> <dstX> <width> <y0> <y1>
//         Copies a box sideways within the same rows, e.g. a clean «o» over a
//         deformed «o» of the same word. Light pixels are shifted by the
//         difference between both backgrounds, so no seam shows on a gradient.
//   shear <in> <out> <x0> <x1> <y0> <y1> <baseY> <shiftPx>
//         Stands a slanted glyph upright: the row at y0 moves <shiftPx> to the
//         left and the row at baseY does not move.
//   mono  <in> <out> <x0> <x1> <y0> <y1> <refX0> <refX1> <refY0> <refY1>
//         Turns a box monochrome with the tint of a reference box, e.g. a
//         line of blue print left inside a black and white photograph.
//
// Measure first with `runs`, patch, then look at the result at 100 %.
// 8-bit RGB or RGBA, non-interlaced PNG only (what the image APIs return).
import fs from 'node:fs';
import zlib from 'node:zlib';

export function readPng(path) {
  const b = fs.readFileSync(path);
  let p = 8, w = 0, h = 0, colorType = 0;
  const idat = [];
  while (p < b.length) {
    const len = b.readUInt32BE(p), type = b.toString('ascii', p + 4, p + 8);
    const data = b.subarray(p + 8, p + 8 + len);
    if (type === 'IHDR') {
      w = data.readUInt32BE(0); h = data.readUInt32BE(4); colorType = data[9];
      if (data[8] !== 8 || data[12] !== 0) throw new Error('Only 8-bit, non-interlaced PNG is supported.');
    }
    if (type === 'IDAT') idat.push(data);
    p += 12 + len;
  }
  if (colorType !== 6 && colorType !== 2) throw new Error(`Unsupported PNG color type ${colorType}.`);
  const bpp = colorType === 6 ? 4 : 3, stride = w * bpp;
  const raw = zlib.inflateSync(Buffer.concat(idat)), px = Buffer.alloc(w * h * 4);
  let prev = Buffer.alloc(stride), cur = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const filter = raw[y * (stride + 1)];
    raw.copy(cur, 0, y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0, up = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      let v = cur[i];
      if (filter === 1) v += a;
      else if (filter === 2) v += up;
      else if (filter === 3) v += (a + up) >> 1;
      else if (filter === 4) {
        const pp = a + up - c, pa = Math.abs(pp - a), pb = Math.abs(pp - up), pc = Math.abs(pp - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c;
      }
      cur[i] = v & 255;
    }
    for (let x = 0; x < w; x++) {
      const o = (y * w + x) * 4;
      px[o] = cur[x * bpp]; px[o + 1] = cur[x * bpp + 1]; px[o + 2] = cur[x * bpp + 2];
      px[o + 3] = bpp === 4 ? cur[x * bpp + 3] : 255;
    }
    [prev, cur] = [cur, prev];
  }
  return { w, h, px };
}

export function writePng(path, { w, h, px }) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    px.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(body) >>> 0);
    return Buffer.concat([len, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  fs.writeFileSync(path, Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]));
}

const luma = (img, x, y) => {
  const i = (y * img.w + x) * 4;
  return img.px[i] * 0.3 + img.px[i + 1] * 0.59 + img.px[i + 2] * 0.11;
};

/** Runs of ink columns in the band, each with its vertical extent. */
export function glyphRuns(img, y0, y1, x0, x1, ink = 'dark', threshold = ink === 'dark' ? 90 : 150) {
  const isInk = (x, y) => (ink === 'dark' ? luma(img, x, y) < threshold : luma(img, x, y) > threshold);
  const runs = [];
  let start = -1;
  for (let x = x0; x <= x1 + 1; x++) {
    let any = false;
    if (x <= x1) for (let y = y0; y <= y1 && !any; y++) any = isInk(x, y);
    if (any && start < 0) start = x;
    if (!any && start >= 0) { runs.push([start, x - 1]); start = -1; }
  }
  return runs.map(([a, b]) => {
    let top = Infinity, bottom = -1;
    for (let x = a; x <= b; x++) for (let y = y0; y <= y1; y++) if (isInk(x, y)) { top = Math.min(top, y); bottom = Math.max(bottom, y); }
    return { x0: a, x1: b, y0: top, y1: bottom };
  });
}

/** Copies a box sideways, compensating the background tone on light pixels. */
export function copyBox(img, srcX, dstX, width, y0, y1) {
  const { w, px } = img;
  const mean = (x) => {
    const s = [0, 0, 0]; let n = 0;
    for (let y = Math.max(0, y0 - 7); y < y0; y++) for (let k = 0; k < width; k++) {
      const i = (y * w + x + k) * 4; s[0] += px[i]; s[1] += px[i + 1]; s[2] += px[i + 2]; n++;
    }
    return s.map((v) => v / Math.max(1, n));
  };
  const from = mean(srcX), to = mean(dstX), delta = to.map((v, k) => v - from[k]);
  // A pixel as light as the source background takes the whole difference; ink takes almost none.
  const fromLuma = Math.max(1, from[0] * 0.3 + from[1] * 0.59 + from[2] * 0.11);
  const patch = [];
  for (let y = y0; y <= y1; y++) for (let k = 0; k < width; k++) {
    const i = (y * w + srcX + k) * 4; patch.push([px[i], px[i + 1], px[i + 2]]);
  }
  let n = 0;
  for (let y = y0; y <= y1; y++) for (let k = 0; k < width; k++) {
    const [r, g, b] = patch[n++], light = Math.min(1, (r * 0.3 + g * 0.59 + b * 0.11) / fromLuma), i = (y * w + dstX + k) * 4;
    [r, g, b].forEach((v, c) => { px[i + c] = Math.max(0, Math.min(255, Math.round(v + delta[c] * light))); });
    px[i + 3] = 255;
  }
}

/** Shears a box so a slanted glyph stands upright. */
export function shearBox(img, x0, x1, y0, y1, baseY, shiftPx) {
  const { w, px } = img, rows = Math.max(1, baseY - y0);
  for (let y = y0; y <= y1; y++) {
    const shift = Math.max(0, shiftPx * (baseY - y) / rows), o = (y * w + x0) * 4;
    const background = [px[o], px[o + 1], px[o + 2]], row = [];
    for (let x = x0; x <= x1; x++) { const i = (y * w + x) * 4; row.push([px[i], px[i + 1], px[i + 2]]); }
    const at = (x) => (x >= x0 && x <= x1 ? row[x - x0] : background);
    for (let x = x0; x <= x1; x++) {
      const fx = x + shift, left = Math.floor(fx), f = fx - left, a = at(left), b = at(left + 1), i = (y * w + x) * 4;
      for (let c = 0; c < 3; c++) px[i + c] = Math.round(a[c] * (1 - f) + b[c] * f);
    }
  }
}

/**
 * Turns a box monochrome with the tint of a reference box: every pixel keeps
 * its lightness and takes the average channel offsets of the reference. For a
 * spot of color left inside a duotone photograph.
 */
export function monoBox(img, x0, x1, y0, y1, refX0, refX1, refY0, refY1) {
  const { w, px } = img, tint = [0, 0, 0];
  let n = 0;
  for (let y = refY0; y <= refY1; y++) for (let x = refX0; x <= refX1; x++) {
    const i = (y * w + x) * 4, l = luma(img, x, y);
    for (let c = 0; c < 3; c++) tint[c] += px[i + c] - l;
    n++;
  }
  for (let c = 0; c < 3; c++) tint[c] /= Math.max(1, n);
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    const i = (y * w + x) * 4, l = luma(img, x, y);
    for (let c = 0; c < 3; c++) px[i + c] = Math.max(0, Math.min(255, Math.round(l + tint[c])));
  }
}

function main(argv) {
  const [command, ...rest] = argv;
  const n = (v) => { const x = Number(v); if (!Number.isFinite(x)) throw new Error(`Not a number: ${v}`); return x; };
  if (command === 'runs') {
    const [png, y0, y1, x0, x1, ink = 'dark', threshold] = rest;
    for (const r of glyphRuns(readPng(png), n(y0), n(y1), n(x0), n(x1), ink, threshold === undefined ? undefined : n(threshold))) {
      console.log(`x ${r.x0}-${r.x1} (w ${r.x1 - r.x0 + 1})  y ${r.y0}-${r.y1}`);
    }
  } else if (command === 'copy') {
    const [input, output, srcX, dstX, width, y0, y1] = rest, img = readPng(input);
    copyBox(img, n(srcX), n(dstX), n(width), n(y0), n(y1)); writePng(output, img);
  } else if (command === 'shear') {
    const [input, output, x0, x1, y0, y1, baseY, shiftPx] = rest, img = readPng(input);
    shearBox(img, n(x0), n(x1), n(y0), n(y1), n(baseY), n(shiftPx)); writePng(output, img);
  } else if (command === 'mono') {
    const [input, output, ...box] = rest, img = readPng(input);
    if (box.length !== 8) throw new Error('mono needs x0 x1 y0 y1 and the reference refX0 refX1 refY0 refY1.');
    monoBox(img, ...box.map(n)); writePng(output, img);
  } else {
    console.error('Usage: png_patch.mjs runs|copy|shear|mono … (see the header of this file)');
    process.exitCode = 2;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) main(process.argv.slice(2));
