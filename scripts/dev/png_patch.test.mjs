// node --test scripts/dev/png_patch.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { copyBox, darkenLine, glyphRuns, monoBox, readPng, shearBox, writePng } from './png_patch.mjs';

/** A sand canvas with black rectangles as «glyphs». */
function canvas(w, h, glyphs, background = [214, 204, 188]) {
  const px = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) { px[i * 4] = background[0]; px[i * 4 + 1] = background[1]; px[i * 4 + 2] = background[2]; px[i * 4 + 3] = 255; }
  for (const [x0, x1, y0, y1] of glyphs) for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) { const i = (y * w + x) * 4; px[i] = px[i + 1] = px[i + 2] = 10; }
  return { w, h, px };
}

test('a PNG written by the tool is read back pixel for pixel', () => {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'png-patch-')), 'a.png');
  const img = canvas(40, 20, [[5, 9, 4, 15], [20, 27, 6, 15]]);
  writePng(file, img);
  const back = readPng(file);
  assert.equal(back.w, 40);
  assert.equal(back.h, 20);
  assert.ok(back.px.equals(img.px));
  fs.rmSync(path.dirname(file), { recursive: true });
});

test('runs finds each glyph with its own extent', () => {
  const img = canvas(40, 20, [[5, 9, 4, 15], [20, 27, 6, 15]]);
  assert.deepEqual(glyphRuns(img, 0, 19, 0, 39), [
    { x0: 5, x1: 9, y0: 4, y1: 15 },
    { x0: 20, x1: 27, y0: 6, y1: 15 },
  ]);
});

test('copy replaces a deformed glyph with the clean one and keeps the local background', () => {
  // The clean glyph sits on a slightly lighter background than the target.
  const img = canvas(60, 30, [[40, 47, 10, 20]]);
  for (let y = 0; y < 30; y++) for (let x = 0; x < 30; x++) { const i = (y * 60 + x) * 4; img.px[i] = 204; img.px[i + 1] = 194; img.px[i + 2] = 178; }
  for (let y = 12; y <= 18; y++) for (let x = 10; x <= 13; x++) { const i = (y * 60 + x) * 4; img.px[i] = img.px[i + 1] = img.px[i + 2] = 10; }
  copyBox(img, 38, 8, 12, 8, 22);
  const at = (x, y) => [...img.px.subarray((y * 60 + x) * 4, (y * 60 + x) * 4 + 3)];
  assert.deepEqual(at(10, 15), [10, 10, 10], 'ink of the clean glyph arrives');
  assert.deepEqual(at(17, 10), [10, 10, 10], 'the whole clean shape arrives, not the deformed one');
  assert.deepEqual(at(9, 15), [204, 194, 178], 'light pixels take the tone of the target background');
});

test('shear stands a slanted stroke upright', () => {
  // A one pixel stroke leaning right: two pixels further right at the top than at the base.
  const img = canvas(30, 20, []);
  for (let y = 4; y <= 14; y++) { const x = 10 + Math.round(2 * (14 - y) / 10); const i = (y * 30 + x) * 4; img.px[i] = img.px[i + 1] = img.px[i + 2] = 10; }
  shearBox(img, 6, 16, 4, 14, 14, 2);
  const darkest = (y) => { let best = 0, value = 255; for (let x = 6; x <= 16; x++) { const v = img.px[(y * 30 + x) * 4]; if (v < value) { value = v; best = x; } } return best; };
  assert.equal(darkest(14), 10);
  assert.equal(darkest(4), 10);
  assert.equal(darkest(9), 10);
});

test('mono removes a spot of color and keeps the tint of the photograph', () => {
  // A warm grey photograph with one blue pixel inside.
  const img = canvas(20, 10, [], [120, 116, 110]);
  const blue = (5 * 20 + 12) * 4;
  img.px[blue] = 20; img.px[blue + 1] = 130; img.px[blue + 2] = 230;
  monoBox(img, 10, 14, 3, 7, 0, 5, 0, 9);
  const [r, g, b] = img.px.subarray(blue, blue + 3);
  assert.ok(r > g && g > b, 'the pixel is warm like the rest, not blue');
  assert.ok(r - b <= 12, 'and it is a grey, not a color');
  assert.deepEqual([...img.px.subarray((5 * 20 + 11) * 4, (5 * 20 + 11) * 4 + 3)], [120, 116, 110], 'grey pixels stay as they were');
});

test('darken-line turns a tan band black and leaves the rest alone', () => {
  // A black tube with a tan band across it, and a tan leaf far from the band.
  const img = canvas(60, 40, [], [30, 30, 32]);
  const paint = (x, y, c) => { const i = (y * 60 + x) * 4; img.px[i] = c[0]; img.px[i + 1] = c[1]; img.px[i + 2] = c[2]; };
  for (let x = 5; x <= 54; x++) for (let y = 18; y <= 22; y++) paint(x, y, [205, 172, 120]);
  paint(30, 4, [205, 172, 120]);
  const changed = darkenLine(img, [[5, 20], [54, 20]], 5);
  assert.ok(changed >= 200, 'the band was found');
  const at = (x, y) => [...img.px.subarray((y * 60 + x) * 4, (y * 60 + x) * 4 + 3)];
  const [r, g, b] = at(30, 20);
  assert.ok(r < 70 && g < 70 && b < 70, 'the band is dark now');
  assert.ok(r > 30, 'and keeps a little sheen over the tube');
  assert.deepEqual(at(30, 4), [205, 172, 120], 'a tan pixel away from the line stays');
  assert.deepEqual(at(30, 30), [30, 30, 32], 'the tube stays');
});
