# Home carousel, November 2026: seven layered slides

This reviewable patch replaces the whole content of the home carousel: the
three slides it had give way to the seven the owner approved on the Claude
Design board «Vinabike.cl con vida» (2026-11-27), in the order he asked for.
It is editor-native data, not a renderer branch or a poster image: every text,
button, product photo and accent is a Canvas layer the inspector reopens, and
the carousel options it sets are controls of the Carousel panel.

## Canonical owners

- Production project: `xzdvtzdqjeyqxnkqprtf`
- Tenant: `5443b130-cc28-45af-a420-cd500b288890`
- Home page: `99b789da-9b2b-44f3-b8d5-5c7bbaf7d5c4`
- Carousel block: `0d155450-981e-4afd-8c74-c5bff74837b8` (its whole `block_data`)

`inicio_carrusel_2026_11.before.json` is the block as it was (three slides:
the workshop, «Consulta por nuestros servicios» and the tubes campaign) and
the guarded rollback target. `inicio_carrusel_2026_11.after.json` is the
reviewed replacement.

## What it holds

| # | Slide (`campaignKey`) | Main button | Other destinations |
|---|---|---|---|
| 1 | `inicio-2026-11-lovasquez` — En bici a Lo Vásquez | `/guias/en-bici-a-lo-vasquez` | `/servicios` |
| 2 | `inicio-2026-11-ninos` — Bicicletas para niños | category Bicicletas | the Freestyle 16 product page, WhatsApp |
| 3 | `inicio-2026-11-servicios` — Servicios | WhatsApp, with the message written | `/servicios` |
| 4 | `inicio-2026-11-maxxis` — Neumáticos Maxxis | brand Maxxis | WhatsApp |
| 5 | `inicio-2026-11-horquillas` — Horquillas RockShox | category Horquillas | the Lyrik Ultimate product page, WhatsApp |
| 6 | `inicio-2026-11-cassette` — Cassette SRAM XS-1270 | its product page (on order) | — |
| 7 | `inicio-2026-11-accesorios` — Luces, candados y bombines | category Accesorios | — |

Each slide carries two compositions of the same content, one layer per
viewport: a desktop one drawn on 1440 × 750 and a narrow one on 390 × 750,
which phones and tablets share. With «El texto acompaña al lienzo»
(`scaleText`) a composition shrinks whole on a narrower screen, and with the
carousel's «El alto acompaña al ancho» (`scaleHeight`) the block's height
follows it, so nothing is cropped between the breakpoints.

The carousel options the block sets: the counter with bars in place of arrows
and dots (`indicatorStyle: bars`, `showArrows: false`), its height on a phone
(`indicatorBottomCompact`), the page's title for search engines and screen
readers (`accessibleTitle`; slide titles are `<h2>`), eight seconds per slide
and a 1.6 s fade. Each slide says which ink the counter takes over it
(`navTone`, per viewport) and whether it needs a plate behind (`navPlate`).

## Media path

The 53 images live in `assets/images/campaigns/inicio-2026-11/` and in the
Carousel image picker's public bucket and prefix, as
`vinabike-assets/website-images/inicio-2026-11-<file>.webp` (immutable cache):

- per slide and viewport, the ground in three image layers — `-center`, at 2×,
  and a `-left` and `-right` bleed that carry the same ground out of focus so a
  wide screen has no hard edge. The ground holds no text and no product;
- the products as transparent cut-outs of the real catalogue photos, a desktop
  and a narrow size where the weight asked for it.

## Prices are typed text

A price on a slide is a text layer, read from the live site on 2026-11-27: it
does not follow the catalogue. When one of these changes, the slide is edited
in the Website Editor (Inicio › Carrusel › the slide › the text layer):

- kids' bikes «Desde $139.990» and the Freestyle 16 at $149.990;
- services at $24.990, $40.000, $70.000 ($90.000 with hydraulic brakes) and
  the brake check at $4.000;
- forks «Desde $511.990» and the Lyrik Ultimate at $1.084.990;
- accessories «desde $4.000».

## Review and apply

The storefront has to be running the renderer that knows these options first
(`services/storefront_html/deploy_cloud_run.sh`); an older one would draw the
slides with dots and unscaled text.

```bash
jq . scripts/website/campaigns/inicio_carrusel_2026_11.after.json
bash scripts/website/campaigns/apply_inicio_carrusel_2026_11.sh apply
```

The apply command refuses to run unless the linked project is production, the
block still holds the reviewed «before», every image a slide names is one of
the 53 reviewed files, and each of those is in Storage with the same bytes. It
writes inside one transaction that locks the block, checks its hash again and
checks the payload's own hash.

## Validate

```bash
bash scripts/website/campaigns/apply_inicio_carrusel_2026_11.sh validate
```

After application, reopen Inicio › Carrusel in the Website Editor, walk the
seven slides in desktop and phone, and open each destination on the public
site.

## Roll back

```bash
bash scripts/website/campaigns/apply_inicio_carrusel_2026_11.sh rollback
```

Rollback restores the three previous slides only while production still holds
the reviewed «after»: once a slide is edited in the Website Editor the hash
changes and the editor's own history is the way back. The images stay in
Storage as unused media; deleting them is unnecessary.
