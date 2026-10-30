# Product Image Quality Pipeline

Conservative product-image tooling for Vinabike ecommerce images.

The pipeline has three modes:

1. `audit`
   - Measures dimensions, blur, file size, subject fill, background quality.
   - Writes `audit.csv`, `audit.jsonl`, and `audit_summary.json`.

2. `process`
   - Creates safe review copies only.
   - Crops obvious whitespace, applies a controlled upscale for tiny sources, centers product on white square canvas, exports WebP.
   - Never uploads or replaces live images.

3. `ai-test`
   - Runs the safe cleanup.
   - Optionally runs Real-ESRGAN when a binary is provided.
   - Writes side-by-side comparison sheets for manual approval.

4. `openai-test`
   - Runs the safe cleanup.
   - Uses the OpenAI Images API to generate a premium product-photo candidate.
   - Writes the prompt metadata and side-by-side comparison sheets for manual approval.

## Runtime

Use the bundled Codex Python when available:

```bash
/Users/Claudio/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/product_image_pipeline.py audit --input path/to/image.jpg
```

The script needs Pillow and NumPy. The bundled runtime already includes them.

## Examples

Audit one image:

```bash
python3 scripts/product_image_pipeline.py audit --input product.jpg
```

Safely standardize one image:

```bash
python3 scripts/product_image_pipeline.py process \
  --input product.jpg \
  --max-safe-upscale 8 \
  --output-dir reports/product_image_test
```

Audit/process a CSV:

```bash
python3 scripts/product_image_pipeline.py process \
  --manifest products.csv \
  --source-column image_url \
  --id-column id \
  --name-column name \
  --output-dir reports/product_image_batch
```

AI upscaling test with Real-ESRGAN:

```bash
python3 scripts/product_image_pipeline.py ai-test \
  --input product.jpg \
  --realesrgan-bin /path/to/realesrgan-ncnn-vulkan \
  --realesrgan-model-dir /path/to/models \
  --realesrgan-model realesrgan-x4plus \
  --realesrgan-scale 4 \
  --output-dir reports/product_image_ai_test
```

If the `models` folder is next to the Real-ESRGAN binary, the script detects it automatically.

AI enhancement test with OpenAI:

```bash
OPENAI_API_KEY=... python3 scripts/product_image_pipeline.py openai-test \
  --input product.jpg \
  --openai-model gpt-image-1.5 \
  --openai-quality high \
  --openai-size 1024x1024 \
  --output-dir reports/product_image_openai_test
```

If Real-ESRGAN is not installed yet, you can still create a non-AI upscale baseline:

```bash
python3 scripts/product_image_pipeline.py ai-test \
  --input product.jpg \
  --allow-lanczos-fallback \
  --output-dir reports/product_image_ai_test
```

That fallback is only a comparison baseline. It is not AI.

## From an official photo to the store (2026-10-29)

A product without a photo is not sold (`product_visibility_require_image`), so a
missing photo hides stock. The ERP lists them in «Catálogo › Por resolver › Sin
foto».

- Use only a photo of the exact product: same model, size, color and version.
  A similar part is worse than no photo.
- Search by the supplier's code first: it is usually the product's SKU.
- Shops built on Shopify answer
  `/search/suggest.json?q=<query>&resources[type]=product` and
  `/products/<handle>.js` with full-size image URLs. That covered the mainstream
  brands (Shimano, SR Suntour, Race Face, VP).
- What did not work on 2026-10-29: comercialciclo.cl did not answer;
  MercadoLibre's API returns 403 and its site shows a security check, which is
  not to be worked around; AliExpress house brands (ZTTO, Deemount, Toopre,
  Muqzi, Wistio, cnSPOKE, Sensah) and generic parts (bearings, spokes, nipples,
  cables, inner tubes) have no trustworthy official photo. Those go to the owner
  to photograph in the shop.
- Process each photo with
  `process --target-size 1400 --margin 100` (`--margin` is whole pixels), then
  save it as JPEG named exactly `<SKU>.jpg`.
- Upload in the ERP: Inventario › Productos › «Edición masiva» › Alcance «Lista
  actual filtrada» › «Imágenes» › «Revisar lote», and drop the files. A file
  named as the SKU finds its product by itself, and «Solo cuando falta imagen»
  is on by default, so an existing photo is never replaced.
- Check afterwards that the product has `image_url` and that `/buscar` on the
  store finds it.

## Safety Rules

- Do not overwrite originals.
- Do not upload processed images automatically.
- Review comparison sheets before replacing product images.
- Use AI modes for tests first, especially for packaging with text/logos.
- If AI changes product labels, logos, colors, or physical details, reject that output.

## Output Folders

- `originals/` copied/downloaded input files
- `processed/` safe WebP outputs
- `ai_previews/` Real-ESRGAN, OpenAI, or baseline upscale outputs
- `comparisons/` side-by-side review images
- `audit.csv` image quality report
- `process_report.csv` generated output report
