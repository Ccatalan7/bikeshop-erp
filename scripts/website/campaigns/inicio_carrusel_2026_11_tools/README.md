# From an approved frame to editor layers

The scripts that turned the seven frames approved on the Claude Design board
into the home carousel of November 2026 (`../inicio_carrusel_2026_11.md`).
They are kept as they ran, as the worked example for the next campaign: the
tables inside them (which frames, which photos, which destinations) are this
campaign's and are rewritten for another one.

All of them work in one folder, `CAMPAIGN_WORK` (default: the current one):

```text
frames/<name>-<d|m>.html   one frame drawn alone: no site header, no counter,
                           the site's own fonts; d = 1440 × 750, m = 390 × 750
src/                       the real product photos the frames use
meas/ art/ out/            what the scripts write
```

| Step | Script | What it does |
|---|---|---|
| 1 | `extract.cjs [name…]` | Measures every text, button, link, product image and accent of each frame into `meas/<name>-<d|m>.json`, then hides them and captures the ground: `art/*-F.png` whole, `art/*-G.png` without what must not be mirrored |
| 2 | `compose.cjs [name…]` | From the ground: the centre image at 2× with 30 px more at the foot, and a bleed for each side — the ground mirrored at the seam, sharp for a safe distance, then out of focus, ending in one flat colour |
| 3 | `alpha.cjs` | The product photos as cut-outs: the white ground becomes transparency |
| 4 | `slides.py <image-base-url> <out.json>` | Assembles the carousel's `block_data`: one layer per measured thing, two compositions per slide, each button with its real destination |
| 5 | `shots.cjs <url> <prefix> <widths> [slides]` | Captures every slide at each width, to compare with the frame |

PNG outputs are converted to WebP (`cwebp`) before upload; the images go to the
media picker's bucket and the block is applied with a guarded script.

What cost time, so it does not again:

- The site draws its heading font as Oswald 400 with a stroke from weight 600
  up, not as a bold: `extract.cjs` measures the text that way, or every width
  is off by a few pixels and lines wrap differently.
- A title is measured upright and the layer leans it (`skew`).
- A text is one layer per line and per style; a link is as wide as its words,
  not as its row.
- The mirrored bleed must not repeat what reads as an object (a number, a
  wheel, a diagonal): those are hidden for the `-G` capture, and each slide
  says how far from its edge the mirror stays sharp (`SAFE`).
- A lazy image inside a hidden set never finishes decoding: a capture script
  waits only for the images that are displayed, with a timeout.
- Verify in a local server against production before publishing; on the live
  site ask for few pages (`docs/wiki/sitio-web/paginas/rendimiento.md`).
