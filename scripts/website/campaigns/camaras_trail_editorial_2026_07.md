# Cámaras trail editorial campaign data patch

This reviewable one-off patch redesigns only slide 3 of the existing home-page
carousel. It deliberately keeps the campaign inside the Website Editor's saved
schema instead of adding renderer constants or flattening the promotion into a
poster image.

## Canonical owners

- Production project: `xzdvtzdqjeyqxnkqprtf`
- Tenant: `5443b130-cc28-45af-a420-cd500b288890`
- Home page: `99b789da-9b2b-44f3-b8d5-5c7bbaf7d5c4`
- Carousel block: `0d155450-981e-4afd-8c74-c5bff74837b8`
- Slide: `block_data.slides[2]`
- Campaign key: `camaras-2026-07`
- Destination: `/productos?category=f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4`

The original `before.json` remains the pre-campaign export. The `v1.json` file
is the first trail-editorial iteration. The `v2.json` file captures the open
product composition before the shared image-source control was enabled and is
now the guarded rollback target. The `after.json` file is the reviewed
editor-native replacement. It retains typed
actions, product bindings, image fallbacks, alternate text, responsive
desktop/mobile ownership, geometry, formatting, animation, focal-point, and
theme-inheritance fields that the inspector can reopen.

## Media path

The generated trail image is uploaded to the same public bucket and
`website-images/` prefix used by the Carousel image picker:

`vinabike-assets/website-images/camaras-trail-editorial-2026-07.png`

The file lives in the Carousel image picker's normal public bucket and
`website-images/` media prefix and is protected by SHA-256 and MD5/eTag checks
in the script. The slide stores its public URL; text, product imagery, accents,
and CTA remain separate Canvas elements.

The three linked catalog products also have presentation-ready transparent PNG
cutouts in the same picker-owned prefix:

- `website-images/camaras-maxxis-welter-weight-29-cutout.png`
- `website-images/camaras-ridexc-butyl-29-cutout.png`
- `website-images/camaras-10ten-butyl-26-cutout.png`

They preserve the six desktop/mobile `productId` bindings. The composition uses
open editorial framing and subtle guide shapes instead of white catalog-image
rectangles inside a large floating card. Every image, guide, label, and position
remains a normal selectable Canvas layer.

## Review and apply

```bash
jq . scripts/website/campaigns/camaras_trail_editorial_2026_07.after.json
bash scripts/website/campaigns/apply_camaras_trail_editorial_2026_07.sh apply
```

The apply command refuses to run unless the linked project, local asset,
current slide hash, storage object checksum, campaign key, typed category
action, and six desktop/mobile product bindings match the reviewed state.

## Validate

```bash
bash scripts/website/campaigns/apply_camaras_trail_editorial_2026_07.sh validate
```

After application, also reopen Home > Carousel > Slide 3 in the Website Editor,
select desktop and mobile layers, compare Edit/Preview/public geometry, exercise
the category CTA, then save/reload only if further manual changes were made.

## Roll back

```bash
bash scripts/website/campaigns/apply_camaras_trail_editorial_2026_07.sh rollback
```

Rollback restores the exact v2 slide JSON only when production still matches
the reviewed after-state hash. Immutable background and cutout objects remain
in Storage as unused assets; deleting them is unnecessary and would make the
recovery path destructive. Remove them later only after a separate
zero-reference audit.
